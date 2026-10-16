/*
 * stage1.c — 本物の OS (Ubuntu のユーザーランド) を見つけて起動を引き継ぐ
 *
 * カーネルのコマンドラインで動きを決める:
 *   root=UUID=... / root=LABEL=... / root=/dev/sdXN
 *       インストール済みの WasabiOS。そのパーティションをマウントして起動する。
 *   wasabi.live
 *       ライブ USB / DVD。/wasabios/root.squashfs を持つメディアを探して読み込み専用でマウントし、
 *       書き込み用の層 (overlay) を重ねる。WASABI-DATA というラベルの ext4 パーティションがあれば
 *       そこに変更を保存する (= 電源を切っても消えない)。無ければメモリ上 (tmpfs)。
 *   wasabi.toram     ライブのとき squashfs をメモリにコピーしてから起動 (USB を抜ける)
 *   init=/path       引き継ぎ先 (既定は /sbin/init = systemd)
 *   rootwait=秒      デバイスが現れるのを待つ時間 (既定 30 秒)
 *
 * 失敗したら戻ってくるので、呼び出し側でレスキュー用のシェルを出す。
 */
#define _GNU_SOURCE
#include "stage1.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/loop.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define NEWROOT  "/newroot"
#define LIVE_DIR "/run/wasabi"
#define SQUASHFS_PATH "wasabios/root.squashfs"

static char cmdline[4096];

static void read_cmdline(void)
{
	FILE *f = fopen("/proc/cmdline", "r");
	if (f) {
		if (!fgets(cmdline, sizeof(cmdline), f))
			cmdline[0] = '\0';
		fclose(f);
	}
	cmdline[strcspn(cmdline, "\n")] = '\0';
}

/* "key=value" の value を返す (無ければ NULL)。key だけのフラグは "" を返す */
static const char *param(const char *key)
{
	static char val[512];
	size_t klen = strlen(key);
	const char *p = cmdline;
	while (*p) {
		while (*p == ' ')
			p++;
		const char *end = strchr(p, ' ');
		size_t len = end ? (size_t)(end - p) : strlen(p);
		if (len >= klen && strncmp(p, key, klen) == 0) {
			if (len == klen) {
				val[0] = '\0';
				return val;
			}
			if (p[klen] == '=') {
				size_t vlen = len - klen - 1;
				if (vlen >= sizeof(val))
					vlen = sizeof(val) - 1;
				memcpy(val, p + klen + 1, vlen);
				val[vlen] = '\0';
				return val;
			}
		}
		p += len;
	}
	return NULL;
}

/* BusyBox のコマンドを実行し、標準出力の1行目を受け取る */
static int run_capture(char *out, size_t outlen, char *const argv[])
{
	int fds[2];
	if (pipe(fds) < 0)
		return -1;
	pid_t pid = fork();
	if (pid == 0) {
		dup2(fds[1], 1);
		close(fds[0]);
		close(fds[1]);
		int null = open("/dev/null", O_WRONLY);
		if (null >= 0)
			dup2(null, 2);
		execv(argv[0], argv);
		_exit(127);
	}
	close(fds[1]);
	ssize_t n = read(fds[0], out, outlen - 1);
	close(fds[0]);
	out[n > 0 ? n : 0] = '\0';
	out[strcspn(out, "\n")] = '\0';
	int st;
	waitpid(pid, &st, 0);
	return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

/* UUID=... / LABEL=... を /dev/xxx に変換する (BusyBox の findfs を使う) */
static int resolve_device(const char *spec, char *dev, size_t devlen)
{
	if (spec[0] == '/') {
		snprintf(dev, devlen, "%s", spec);
		return access(dev, F_OK) == 0 ? 0 : -1;
	}
	char *argv[] = { "/bin/busybox", "findfs", (char *)spec, NULL };
	return run_capture(dev, devlen, argv) == 0 && dev[0] ? 0 : -1;
}

static const char *ROOT_TYPES[] = { "ext4", "btrfs", "xfs", NULL };
/* ライブメディアは ISO (DVD / dd した USB) か FAT/exFAT (ファイルをコピーした USB)。
 * 内蔵 SSD の ext4 などは、読み込み専用でもジャーナルの書き戻しが起きうるので触らない */
static const char *LIVE_TYPES[] = { "iso9660", "vfat", "exfat", NULL };

static int try_mount(const char *dev, const char *target, unsigned long flags,
		     const char *const types[])
{
	mkdir(target, 0755);
	for (int i = 0; types[i]; i++)
		if (mount(dev, target, types[i], flags, NULL) == 0)
			return 0;
	return -1;
}

static int rootwait_seconds(void)
{
	const char *w = param("rootwait");
	return (w && *w) ? atoi(w) : 30;
}

/* ---- ループデバイス (ファイルをディスクとして扱う) ---- */
static int attach_loop(const char *file, char *loopdev, size_t len)
{
	int ctl = open("/dev/loop-control", O_RDWR | O_CLOEXEC);
	if (ctl < 0)
		return -1;
	int n = ioctl(ctl, LOOP_CTL_GET_FREE);
	close(ctl);
	if (n < 0)
		return -1;
	snprintf(loopdev, len, "/dev/loop%d", n);

	int ffd = open(file, O_RDONLY | O_CLOEXEC);
	int lfd = open(loopdev, O_RDWR | O_CLOEXEC);
	if (ffd < 0 || lfd < 0)
		return -1;
	struct loop_config cfg = { .fd = (unsigned)ffd };
	cfg.info.lo_flags = LO_FLAGS_READ_ONLY | LO_FLAGS_AUTOCLEAR;
	snprintf((char *)cfg.info.lo_file_name, LO_NAME_SIZE, "%s", file);
	int r = ioctl(lfd, LOOP_CONFIGURE, &cfg);
	close(ffd);
	close(lfd);
	return r;
}

static int copy_file(const char *from, const char *to)
{
	int in = open(from, O_RDONLY), out = open(to, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (in < 0 || out < 0)
		return -1;
	char buf[1 << 20];
	ssize_t n;
	while ((n = read(in, buf, sizeof(buf))) > 0)
		if (write(out, buf, n) != n)
			return -1;
	close(in);
	close(out);
	return n < 0 ? -1 : 0;
}

/* ---- ライブ起動 ---- */

/* /sys/class/block の全デバイスを試して、root.squashfs を持つメディアを探す */
static int find_live_media(char *found, size_t len)
{
	DIR *d = opendir("/sys/class/block");
	if (!d)
		return -1;
	struct dirent *e;
	int ok = -1;
	while (ok < 0 && (e = readdir(d))) {
		if (e->d_name[0] == '.' || strncmp(e->d_name, "loop", 4) == 0 ||
		    strncmp(e->d_name, "ram", 3) == 0)
			continue;
		char dev[300];
		snprintf(dev, sizeof(dev), "/dev/%s", e->d_name);
		if (try_mount(dev, LIVE_DIR "/media", MS_RDONLY, LIVE_TYPES) < 0)
			continue;
		if (access(LIVE_DIR "/media/" SQUASHFS_PATH, R_OK) == 0) {
			snprintf(found, len, "%s", dev);
			ok = 0;
		} else {
			umount(LIVE_DIR "/media");
		}
	}
	closedir(d);
	return ok;
}

static int setup_live(void)
{
	mkdir(LIVE_DIR, 0755);
	char media[300] = "";
	int wait = rootwait_seconds();
	say("Looking for WasabiOS live media...");
	for (int t = 0; find_live_media(media, sizeof(media)) < 0; t++) {
		if (t >= wait * 2) {
			say("No live media with /" SQUASHFS_PATH " found");
			return -1;
		}
		usleep(500000); /* USB は見えるまで少しかかる */
	}
	say("Live media: %s", media);

	char squash[256] = LIVE_DIR "/media/" SQUASHFS_PATH;
	if (param("wasabi.toram")) {
		say("Copying the system to RAM (wasabi.toram)...");
		mkdir(LIVE_DIR "/ram", 0755);
		mount("tmpfs", LIVE_DIR "/ram", "tmpfs", 0, "mode=0755");
		if (copy_file(squash, LIVE_DIR "/ram/root.squashfs") == 0) {
			snprintf(squash, sizeof(squash), LIVE_DIR "/ram/root.squashfs");
		} else {
			say("Not enough RAM, booting from the media instead");
		}
	}

	char loopdev[32];
	if (attach_loop(squash, loopdev, sizeof(loopdev)) < 0) {
		say("Could not set up a loop device: %s", strerror(errno));
		return -1;
	}
	mkdir(LIVE_DIR "/ro", 0755);
	if (mount(loopdev, LIVE_DIR "/ro", "squashfs", MS_RDONLY, NULL) < 0) {
		say("Could not mount the squashfs: %s", strerror(errno));
		return -1;
	}
	if (param("wasabi.toram"))
		umount2(LIVE_DIR "/media", MNT_DETACH);

	/* 書き込み層: WASABI-DATA があればそこ (保存される)、無ければメモリ */
	mkdir(LIVE_DIR "/rw", 0755);
	char data[64];
	if (resolve_device("LABEL=WASABI-DATA", data, sizeof(data)) == 0 &&
	    mount(data, LIVE_DIR "/rw", "ext4", MS_NOATIME, NULL) == 0) {
		say("Persistent storage: %s (changes are kept)", data);
	} else {
		mount("tmpfs", LIVE_DIR "/rw", "tmpfs", 0, "mode=0755");
		say("No WASABI-DATA partition: changes are kept in RAM only");
	}
	mkdir(LIVE_DIR "/rw/upper", 0755);
	mkdir(LIVE_DIR "/rw/work", 0755);

	mkdir(NEWROOT, 0755);
	if (mount("overlay", NEWROOT, "overlay", 0,
		  "lowerdir=" LIVE_DIR "/ro,upperdir=" LIVE_DIR "/rw/upper,workdir=" LIVE_DIR "/rw/work") < 0) {
		say("Could not mount the overlay: %s", strerror(errno));
		return -1;
	}
	return 0;
}

/* ---- インストール済みの OS ---- */
static int setup_installed(const char *spec)
{
	char dev[128];
	int wait = rootwait_seconds();
	say("Waiting for root device %s...", spec);
	for (int t = 0; resolve_device(spec, dev, sizeof(dev)) < 0; t++) {
		if (t >= wait * 2) {
			say("Root device %s not found", spec);
			return -1;
		}
		usleep(500000);
	}
	unsigned long flags = param("rw") ? 0 : MS_RDONLY; /* systemd があとで書き込み可能にする */
	if (try_mount(dev, NEWROOT, flags, ROOT_TYPES) < 0) {
		say("Could not mount %s: %s", dev, strerror(errno));
		return -1;
	}
	say("Root: %s", dev);
	return 0;
}

/* ---- switch_root: initramfs から本物のルートへ乗り換える ---- */

/* initramfs (メモリ上) のファイルを消してメモリを空ける。マウントされた先には入らない */
static void delete_tree(int dfd, dev_t rootdev)
{
	DIR *d = fdopendir(dfd);
	if (!d)
		return;
	struct dirent *e;
	while ((e = readdir(d))) {
		if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, ".."))
			continue;
		struct stat st;
		if (fstatat(dfd, e->d_name, &st, AT_SYMLINK_NOFOLLOW) < 0 || st.st_dev != rootdev)
			continue;
		if (S_ISDIR(st.st_mode)) {
			int sub = openat(dfd, e->d_name, O_RDONLY | O_DIRECTORY);
			if (sub >= 0)
				delete_tree(sub, rootdev);
			unlinkat(dfd, e->d_name, AT_REMOVEDIR);
		} else {
			unlinkat(dfd, e->d_name, 0);
		}
	}
	closedir(d);
}

static int switch_root(const char *init)
{
	char path[256];
	snprintf(path, sizeof(path), NEWROOT "%s", init);
	if (access(path, X_OK) < 0) {
		say("%s is not in the root filesystem", init);
		return -1;
	}

	static const char *moves[] = { "/dev", "/proc", "/sys", "/run" };
	for (size_t i = 0; i < sizeof(moves) / sizeof(moves[0]); i++) {
		snprintf(path, sizeof(path), NEWROOT "%s", moves[i]);
		mkdir(path, 0755);
		if (mount(moves[i], path, NULL, MS_MOVE, NULL) < 0)
			say("move %s: %s", moves[i], strerror(errno));
	}
	umount2("/tmp", MNT_DETACH);

	if (chdir(NEWROOT) < 0)
		return -1;
	struct stat st;
	if (stat("/", &st) == 0) {
		int fd = open("/", O_RDONLY | O_DIRECTORY);
		if (fd >= 0)
			delete_tree(fd, st.st_dev);
	}
	if (mount(".", "/", NULL, MS_MOVE, NULL) < 0 || chroot(".") < 0 || chdir("/") < 0) {
		say("switch_root failed: %s", strerror(errno));
		return -1;
	}

	/* 標準入出力をコンソールにつなぎ直して、systemd などへ */
	int con = open("/dev/console", O_RDWR);
	if (con >= 0) {
		dup2(con, 0);
		dup2(con, 1);
		dup2(con, 2);
		if (con > 2)
			close(con);
	}
	execl(init, init, (char *)NULL);
	say("Could not start %s: %s", init, strerror(errno));
	return -1;
}

int stage1_boot(void)
{
	read_cmdline();
	const char *root = param("root");
	int live = param("wasabi.live") != NULL;
	if (!live && !root)
		return 1; /* 何も指定が無い = この initramfs 自体が OS (レスキュー/シード) */

	char init[256] = "/sbin/init";
	const char *i = param("init");
	if (i && *i)
		snprintf(init, sizeof(init), "%s", i);

	int r = live ? setup_live() : setup_installed(root);
	if (r == 0) {
		say("Starting %s", init);
		switch_root(init);
	}
	say("Boot failed. Dropping to a rescue shell (type 'reboot' to retry).");
	return -1;
}
