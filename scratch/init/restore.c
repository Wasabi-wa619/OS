/*
 * restore.c — WasabiOS の「前の状態に戻す」機能 (Chrome OS のような復元)
 *
 * インストール済みの WasabiOS は btrfs の上に次の「サブボリューム」を持つ:
 *   @            システム本体 (/ にマウントされる)
 *   @home        自分のファイル (/home)。戻しても消えない
 *   @snapshots   保存しておいたシステムの状態 (/.snapshots)
 *                  2026-10-17_031000_apt     アップデート前に自動で保存されたもの
 *                  factory                   インストール直後の状態 (パワーウォッシュ用)
 *
 * 戻すときは OS が起動する前 (ここ) で、@ を @broken-日時 に名前を変え、
 * 選んだスナップショットから新しい @ を作って再起動する。
 * OS が壊れて起動しなくなっていても、起動メニューから戻せる。
 *
 * 戻すきっかけ:
 *   wasabi.rollback=menu     起動メニューの「前の状態に戻す」。一覧から選ぶ画面を出す
 *   wasabi.rollback=<名前>   そのスナップショットに戻す
 *   @snapshots/.rollback-request   動いている OS で `wasabi rollback <名前>` したときに書かれる
 */
#define _GNU_SOURCE
#include "stage1.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/btrfs.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define TOP "/run/wasabi/top"
#define SNAPDIR TOP "/@snapshots"
#define REQUEST SNAPDIR "/.rollback-request"
#define MAX_SNAPS 64

/* btrfs のスナップショットを作る (src の状態を dstdir/name に) */
static int btrfs_snapshot(const char *src, const char *dstdir, const char *name, int readonly)
{
	int s = open(src, O_RDONLY | O_DIRECTORY);
	int d = open(dstdir, O_RDONLY | O_DIRECTORY);
	int r = -1;
	if (s >= 0 && d >= 0) {
		struct btrfs_ioctl_vol_args_v2 a;
		memset(&a, 0, sizeof(a));
		a.fd = s;
		a.flags = readonly ? BTRFS_SUBVOL_RDONLY : 0;
		snprintf(a.name, sizeof(a.name), "%s", name);
		r = ioctl(d, BTRFS_IOC_SNAP_CREATE_V2, &a);
	}
	if (s >= 0)
		close(s);
	if (d >= 0)
		close(d);
	return r;
}

static int by_name_desc(const void *a, const void *b)
{
	return strcmp(*(char *const *)b, *(char *const *)a);
}

/* @snapshots の中身を新しい順に並べる (factory は最後) */
static int list_snapshots(char *names[], int max)
{
	DIR *d = opendir(SNAPDIR);
	if (!d)
		return 0;
	int n = 0;
	int has_factory = 0;
	struct dirent *e;
	while ((e = readdir(d)) && n < max - 1) {
		if (e->d_name[0] == '.')
			continue;
		if (!strcmp(e->d_name, "factory")) {
			has_factory = 1;
			continue;
		}
		names[n++] = strdup(e->d_name);
	}
	closedir(d);
	qsort(names, n, sizeof(names[0]), by_name_desc);
	if (has_factory)
		names[n++] = strdup("factory");
	return n;
}

/* "2026-10-17_031000_apt" → "2026-10-17 03:10  apt" */
static void pretty(const char *name, char *out, size_t len)
{
	if (!strcmp(name, "factory")) {
		snprintf(out, len, "Factory reset (the state right after installation)");
		return;
	}
	int Y, M, D, h, m, s;
	char label[200] = "";
	if (sscanf(name, "%4d-%2d-%2d_%2d%2d%2d_%199s", &Y, &M, &D, &h, &m, &s, label) >= 6)
		snprintf(out, len, "%04d-%02d-%02d %02d:%02d  %s", Y, M, D, h, m, label);
	else
		snprintf(out, len, "%s", name);
}

static int do_rollback(const char *name)
{
	char src[512];
	snprintf(src, sizeof(src), SNAPDIR "/%s", name);
	if (access(src, F_OK) < 0) {
		say("Snapshot '%s' not found", name);
		return -1;
	}

	/* 今のシステムは消さずに @broken-日時 として残しておく (失敗したときの保険) */
	char broken[64];
	time_t now = time(NULL);
	strftime(broken, sizeof(broken), "@broken-%Y%m%d-%H%M%S", localtime(&now));
	int top = open(TOP, O_RDONLY | O_DIRECTORY);
	if (top < 0 || renameat(top, "@", top, broken) < 0) {
		say("Could not move the current system aside: %s", strerror(errno));
		return -1;
	}
	if (btrfs_snapshot(src, TOP, "@", 0) < 0) {
		say("Could not restore '%s': %s", name, strerror(errno));
		renameat(top, broken, top, "@"); /* 元に戻す */
		close(top);
		return -1;
	}
	close(top);
	unlink(REQUEST);
	sync();
	say("Restored the system to '%s'. The previous system was kept as %s.", name, broken);
	return 0;
}

/* 一覧から選ぶ画面 (Linux コンソールは日本語を出せないので英語) */
static const char *menu(char *names[], int n)
{
	FILE *con = fopen("/dev/console", "r+");
	if (!con)
		return NULL;
	setvbuf(con, NULL, _IONBF, 0);
	for (;;) {
		fprintf(con, "\n\033[1;32m  WasabiOS Restore\033[0m\n"
			     "  ----------------\n"
			     "  Choose the point to go back to. Only the system goes back:\n"
			     "  your files in /home are kept.\n\n");
		for (int i = 0; i < n; i++) {
			char p[256];
			pretty(names[i], p, sizeof(p));
			if (!strcmp(names[i], "factory"))
				fprintf(con, "   F) %s\n", p);
			else
				fprintf(con, "  %2d) %s\n", i + 1, p);
		}
		if (n == 0)
			fprintf(con, "  (no snapshots yet)\n");
		fprintf(con, "\n   0) Cancel and start WasabiOS normally\n\n  Your choice: ");

		char line[32];
		if (!fgets(line, sizeof(line), con))
			break;
		if (line[0] == '0' || line[0] == '\n')
			break;
		int idx = -1;
		if (line[0] == 'f' || line[0] == 'F') {
			for (int i = 0; i < n; i++)
				if (!strcmp(names[i], "factory"))
					idx = i;
		} else {
			idx = atoi(line) - 1;
		}
		if (idx < 0 || idx >= n || (line[0] != 'f' && line[0] != 'F' && !strcmp(names[idx], "factory"))) {
			fprintf(con, "  Invalid choice.\n");
			continue;
		}
		char p[256];
		pretty(names[idx], p, sizeof(p));
		fprintf(con, "\n  Go back to: %s\n  Type 'yes' to continue: ", p);
		if (fgets(line, sizeof(line), con) && !strncmp(line, "yes", 3)) {
			fclose(con);
			return names[idx];
		}
	}
	fclose(con);
	return NULL;
}

int restore_check(const char *dev, const char *how)
{
	mkdir("/run/wasabi", 0755);
	mkdir(TOP, 0755);
	if (mount(dev, TOP, "btrfs", 0, "subvolid=5") < 0)
		return 0; /* btrfs ではない (ext4 など) → 何もしない */

	char want[256] = "";
	FILE *f = fopen(REQUEST, "r");
	if (f) {
		if (fgets(want, sizeof(want), f))
			want[strcspn(want, "\n")] = '\0';
		fclose(f);
		if (want[0])
			say("Rollback requested: %s", want);
	}

	char *names[MAX_SNAPS];
	int n = list_snapshots(names, MAX_SNAPS);
	const char *target = want[0] ? want : NULL;
	if (how && !strcmp(how, "menu"))
		target = menu(names, n);
	else if (how && *how)
		target = how;

	int r = 0;
	if (target) {
		r = do_rollback(target) == 0 ? 1 : 0;
	}
	for (int i = 0; i < n; i++)
		free(names[i]);
	if (!r)
		unlink(REQUEST); /* 失敗した依頼を毎回くり返さない */
	umount(TOP);

	if (r) {
		say("Rebooting into the restored system...");
		sleep(2);
		sync();
		reboot(RB_AUTOBOOT);
	}
	return 0;
}
