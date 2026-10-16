/* wasabi-init: 本物の OS へ起動を引き継ぐ部分 (stage1.c) */
#ifndef WASABI_STAGE1_H
#define WASABI_STAGE1_H

/* wasabi-init.c にある画面への表示 */
void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

/*
 * カーネルのコマンドラインに root= か wasabi.live があれば、OS を探して起動を引き継ぐ (成功すると戻らない)。
 * 指定が無ければ 1、起動に失敗したら -1 を返す。どちらの場合もこの initramfs の中でシェルを出す。
 */
int stage1_boot(void);

#endif
