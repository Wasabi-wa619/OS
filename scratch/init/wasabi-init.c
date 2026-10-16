/*
 * wasabi-init — WasabiOS の PID 1 (カーネルが最初に起動するプログラム)
 * 画面 (Linux コンソール) は日本語を表示できないので、表示する文字は英語にしている。
 *
 * やること:
 *   1. /proc /sys /dev などの特別なファイルシステムをマウント
 *   2. カーネルのコマンドラインに root= か wasabi.live があれば、本物の OS (Ubuntu のユーザーランド) を
 *      探してマウントし、systemd に起動を引き継ぐ (stage1.c)。ここで終わり。
 *   3. 引き継ぐ OS が無いとき (シード版)・失敗したとき (レスキュー) は、この initramfs 自体を OS として動かす:
 *      a. ホスト名の設定、/etc/rc.d/ の起動スクリプトを番号順に実行
 *      b. 各画面 (tty1〜tty3 とシリアル) でシェルを起動し、終了したら起動し直す
 *      c. 親のいなくなったプロセス (ゾンビ) を回収する
 *      d. poweroff / reboot の合図 (シグナル) が来たら、全プロセスを止めて電源を切る
 *
 * シグナルの約束は BusyBox の poweroff / reboot / halt コマンドに合わせている:
 *   SIGUSR2 = 電源オフ, SIGTERM = 再起動, SIGUSR1 = 停止
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#include "stage1.h"

#define GREEN "\033[1;32m"
#define DIM   "\033[2m"
#define RESET "\033[0m"

/* シェルを出す端末。存在しないものは飛ばす */
static const char *TTYS[] = { "/dev/tty1", "/dev/tty2", "/dev/tty3", "/dev/ttyS0" };
#define NTTY (sizeof(TTYS) / sizeof(TTYS[0]))

static pid_t shell_pid[NTTY];
static time_t last_start[NTTY];
static volatile sig_atomic_t shutdown_request; /* 0=なし, それ以外=reboot() に渡す値 */

void say(const char *fmt, ...)
{
	va_list ap;
	FILE *con = fopen("/dev/console", "w");
	if (!con)
		return;
	fputs(GREEN " * " RESET, con);
	va_start(ap, fmt);
	vfprintf(con, fmt, ap);
	va_end(ap);
	fputc('\n', con);
	fclose(con);
}

static void mount_fs(const char *src, const char *target, const char *type,
		     unsigned long flags, const char *data)
{
	mkdir(target, 0755);
	if (mount(src, target, type, flags, data) < 0 && errno != EBUSY)
		say("failed to mount %s: %s", target, strerror(errno));
}

static void mount_all(void)
{
	mount_fs("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	mount_fs("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
	mount_fs("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755");
	mount_fs("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC, "gid=5,mode=620,ptmxmode=666");
	mount_fs("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
	mount_fs("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");
	mount_fs("tmpfs", "/tmp", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
	/* EFI 変数 (UEFI で起動したときだけ存在する) */
	if (access("/sys/firmware/efi", F_OK) == 0)
		mount_fs("efivarfs", "/sys/firmware/efi/efivars", "efivarfs",
			 MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
}

static void set_hostname(void)
{
	char name[64] = "wasabi";
	FILE *f = fopen("/etc/hostname", "r");
	if (f) {
		if (fgets(name, sizeof(name), f))
			name[strcspn(name, "\n")] = '\0';
		fclose(f);
	}
	if (sethostname(name, strlen(name)) < 0)
		say("failed to set hostname: %s", strerror(errno));
}

/* /etc/rc.d/ の中のスクリプトを名前順に実行 (01-xxx, 10-yyy ...) */
static int by_name(const struct dirent **a, const struct dirent **b)
{
	return strcmp((*a)->d_name, (*b)->d_name);
}

static void run_rc(void)
{
	struct dirent **list;
	int n = scandir("/etc/rc.d", &list, NULL, by_name);
	for (int i = 0; i < n; i++) {
		char path[512];
		snprintf(path, sizeof(path), "/etc/rc.d/%s", list[i]->d_name);
		if (list[i]->d_name[0] != '.' && access(path, X_OK) == 0) {
			pid_t pid = fork();
			if (pid == 0) {
				execl(path, path, (char *)NULL);
				_exit(127);
			}
			int st;
			waitpid(pid, &st, 0);
			if (!WIFEXITED(st) || WEXITSTATUS(st) != 0)
				say("%s failed", list[i]->d_name);
		}
		free(list[i]);
	}
	if (n > 0)
		free(list);
}

static pid_t spawn_shell(const char *tty)
{
	pid_t pid = fork();
	if (pid != 0)
		return pid;

	/* 子プロセス: 新しいセッションを作り、その端末を「自分の画面」にする */
	sigset_t none;
	sigemptyset(&none);
	sigprocmask(SIG_SETMASK, &none, NULL);
	setsid();
	int fd = open(tty, O_RDWR | O_NOCTTY);
	if (fd < 0)
		_exit(1);
	ioctl(fd, TIOCSCTTY, 1);
	dup2(fd, 0);
	dup2(fd, 1);
	dup2(fd, 2);
	if (fd > 2)
		close(fd);

	setenv("HOME", "/root", 1);
	setenv("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", 1);
	setenv("TERM", strncmp(tty, "/dev/ttyS", 9) == 0 ? "vt100" : "linux", 1);
	setenv("SHELL", "/bin/sh", 1);
	if (chdir("/root") < 0 && chdir("/") < 0)
		_exit(1);
	execl("/bin/sh", "-sh", (char *)NULL); /* 先頭の "-" はログインシェルの印 */
	_exit(127);
}

static int tty_usable(const char *tty)
{
	int fd = open(tty, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0)
		return 0;
	/* シリアルポートは実際につながっているときだけ使う */
	struct termios t;
	int ok = tcgetattr(fd, &t) == 0;
	close(fd);
	return ok;
}

static void on_signal(int sig)
{
	switch (sig) {
	case SIGUSR2: shutdown_request = RB_POWER_OFF; break;
	case SIGTERM: shutdown_request = RB_AUTOBOOT; break;
	case SIGUSR1: shutdown_request = RB_HALT_SYSTEM; break;
	case SIGINT:  shutdown_request = RB_AUTOBOOT; break; /* Ctrl+Alt+Del */
	case SIGALRM: break; /* waitpid から起こすだけ */
	}
}

static void shutdown_system(int how)
{
	say("%s...", how == RB_POWER_OFF ? "Powering off" :
		     how == RB_AUTOBOOT ? "Rebooting" : "Halting");
	kill(-1, SIGTERM);
	sleep(2);
	kill(-1, SIGKILL);
	while (waitpid(-1, NULL, WNOHANG) > 0)
		;
	sync();
	umount2("/tmp", MNT_DETACH);
	umount2("/run", MNT_DETACH);
	sync();
	reboot(how);
	for (;;)
		pause();
}

static void banner(void)
{
	char ver[128] = "";
	FILE *f = fopen("/etc/wasabios-release", "r");
	if (f) {
		if (fgets(ver, sizeof(ver), f))
			ver[strcspn(ver, "\n")] = '\0';
		fclose(f);
	}
	FILE *con = fopen("/dev/console", "w");
	if (!con)
		return;
	fprintf(con, "\n" GREEN
		"   ▄██▄   ▄██▄\n"
		"  ████████████    %s\n"
		"  ▀██████████▀    " RESET DIM "booting with wasabi-init (PID 1)" RESET GREEN "\n"
		"    ▀██████▀\n"
		"      ▀██▀\n"
		"       ▐▌\n" RESET "\n", ver);
	fclose(con);
}

int main(void)
{
	if (getpid() != 1) {
		fprintf(stderr, "wasabi-init must run as PID 1\n");
		return 1;
	}

	/* シグナルは main ループの中でまとめて処理する */
	struct sigaction sa = { .sa_handler = on_signal };
	sigemptyset(&sa.sa_mask);
	sigaction(SIGUSR1, &sa, NULL);
	sigaction(SIGUSR2, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGALRM, &sa, NULL);
	reboot(RB_DISABLE_CAD); /* Ctrl+Alt+Del で即リセットせず SIGINT を受け取る */

	setenv("PATH", "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", 1);
	umask(022);
	mount_all();
	banner();

	/* 本物の OS があれば起動を引き継ぐ (成功したらここには戻らない) */
	int r = stage1_boot();

	set_hostname();
	if (r > 0) { /* シード版: この initramfs が OS */
		say("Running /etc/rc.d scripts");
		run_rc();
	}
	say("Ready. Alt+F1..F3 switches between consoles");

	for (;;) {
		/* シェルが動いていない端末に起動し直す (連続で落ちるときは少し待つ) */
		for (size_t i = 0; i < NTTY; i++) {
			if (shell_pid[i] > 0 || !tty_usable(TTYS[i]))
				continue;
			if (time(NULL) - last_start[i] < 2) {
				alarm(2); /* 2秒後にもう一度見に来る */
				continue;
			}
			last_start[i] = time(NULL);
			shell_pid[i] = spawn_shell(TTYS[i]);
		}

		if (shutdown_request)
			shutdown_system(shutdown_request);

		/* 子プロセスの終了を待つ (ゾンビ回収)。シグナルで起こされることもある */
		int st;
		pid_t pid = waitpid(-1, &st, 0);
		if (pid < 0) {
			if (errno == ECHILD)
				sleep(1);
			continue;
		}
		for (size_t i = 0; i < NTTY; i++)
			if (shell_pid[i] == pid)
				shell_pid[i] = 0;
	}
}
