#!/usr/bin/env bash
# WasabiOS Scratch をゼロから組み立てる
#   使い方: bash scratch/build.sh          (root 不要)
#           bash scratch/build.sh --tools-only   自作 init と BusyBox だけ作る (build/tools/)
#                                               → フル版 WasabiOS の起動パッケージ (wasabios-boot) に入る
#
#   1. Linux カーネルと BusyBox のソースをダウンロードして検証 (sha256)
#   2. WasabiOS カーネル (kernel/build-kernel.sh で作る .deb。フル版と共通) を取り出す
#   3. BusyBox を静的リンクでビルド (ls や sh などの基本コマンド)
#   4. 自作の init (init/wasabi-init.c) をビルド
#   5. rootfs/ と合わせて initramfs (メモリ上で動くルートファイルシステム) を作る
#   6. GRUB で BIOS / UEFI 両対応の起動 ISO にする
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/versions.conf"
TOOLS_ONLY=""
[ "${1:-}" = "--tools-only" ] && TOOLS_ONLY=1

B="$HERE/build"
SRC="$B/src"
OUT="$HERE/../out"
JOBS="${JOBS:-$(nproc)}"
BUSYBOX_DIR="$B/busybox-$BUSYBOX_VERSION"
ROOT="$B/rootfs"
ISO="$OUT/wasabios-scratch-$WASABI_VERSION-x86_64.iso"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

NEED="gcc make bzip2"
[ -n "$TOOLS_ONLY" ] || NEED="$NEED cpio gzip zstd depmod modprobe dpkg-deb grub-mkrescue xorriso"
for cmd in $NEED; do
  command -v "$cmd" >/dev/null || { echo "$cmd がありません。'make -C scratch deps' を実行してください" >&2; exit 1; }
done
mkdir -p "$SRC" "$OUT"

# ---- 1. ソースの取得 ------------------------------------------------------
fetch() { # fetch URL SHA256
  local file="$SRC/${1##*/}"
  if [ ! -f "$file" ]; then
    log "ダウンロード: ${1##*/}"
    curl -fL --retry 3 -o "$file.part" "$1"
    mv "$file.part" "$file"
  fi
  echo "$2  $file" | sha256sum -c --quiet || { echo "チェックサムが合いません: $file" >&2; exit 1; }
  echo "$file"
}
BUSYBOX_TAR=$(fetch "$BUSYBOX_URL" "$BUSYBOX_SHA256" | tail -1)
[ -d "$BUSYBOX_DIR" ] || { log "BusyBox のソースを展開"; tar -C "$B" -xf "$BUSYBOX_TAR"; }

# ---- 2. カーネル (フル版と同じ WasabiOS カーネル) ------------------------------
if [ -z "$TOOLS_ONLY" ]; then
if ! ls "$OUT"/kernel/linux-image-*.deb >/dev/null 2>&1; then
  bash "$HERE/kernel/build-kernel.sh"
fi
log "WasabiOS カーネルのパッケージを展開"
rm -rf "$B/kernel-pkg"
dpkg-deb -x "$(ls "$OUT"/kernel/linux-image-*.deb | head -1)" "$B/kernel-pkg"
KERNEL=$(ls "$B"/kernel-pkg/boot/vmlinuz-* | head -1)
KVER=${KERNEL##*/vmlinuz-}
fi

# ---- 3. BusyBox -----------------------------------------------------------
log "BusyBox $BUSYBOX_VERSION をビルド"
make -C "$BUSYBOX_DIR" -s defconfig >/dev/null
while IFS= read -r line; do
  case "$line" in
    CONFIG_*=*)            key=${line%%=*}; sed -i "s|^$key=.*|$line|; s|^# $key is not set|$line|" "$BUSYBOX_DIR/.config" ;;
    "# CONFIG_"*" is not set") key=${line#\# }; key=${key%% *}; sed -i "s|^$key=.*|# $key is not set|" "$BUSYBOX_DIR/.config" ;;
  esac
done < "$HERE/busybox/wasabi.config"
# 新しい項目にはすべて既定値で答える (yes が途中で止められるのは正常なので pipefail を外す)
(set +o pipefail; yes "" | make -C "$BUSYBOX_DIR" -s oldconfig >/dev/null)
make -C "$BUSYBOX_DIR" -s -j"$JOBS" busybox 2>&1 | grep -v "warning: Using '.*' in statically linked" || true
[ -x "$BUSYBOX_DIR/busybox" ] || { echo "BusyBox のビルドに失敗しました" >&2; exit 1; }

# ---- 4. 自作 init ---------------------------------------------------------
log "wasabi-init (自作の PID 1) をビルド"
mkdir -p "$B/init"
gcc -static -O2 -Wall -Wextra -o "$B/init/wasabi-init" "$HERE/init/wasabi-init.c" "$HERE/init/stage1.c" "$HERE/init/restore.c"

if [ -n "$TOOLS_ONLY" ]; then
  mkdir -p "$B/tools"
  install -m755 "$B/init/wasabi-init" "$B/tools/wasabi-init"
  install -m755 "$BUSYBOX_DIR/busybox" "$B/tools/busybox"
  log "完成: $B/tools/ (wasabi-init, busybox)"
  exit 0
fi

# ---- 5. ルートファイルシステム (initramfs) --------------------------------
log "ルートファイルシステムを組み立て"
rm -rf "$ROOT"
mkdir -p "$ROOT"/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,run,tmp,root,etc,lib/modules}
cp -a "$HERE/rootfs/." "$ROOT/"
install -m755 "$BUSYBOX_DIR/busybox" "$ROOT/bin/busybox"
# busybox の各コマンド (ls, cp, vi ...) をリンクとして作る
for app in $("$ROOT/bin/busybox" --list-full); do
  [ -e "$ROOT/$app" ] || ln -s /bin/busybox "$ROOT/$app"
done
install -m755 "$B/init/wasabi-init" "$ROOT/init"   # カーネルは initramfs の /init を最初に起動する
ln -sf /init "$ROOT/sbin/init"
chmod 700 "$ROOT/root"
chmod 1777 "$ROOT/tmp"

# ドライバー (カーネルモジュール): modules.list に書いたものと、それが必要とするものだけ持っていく
log "ドライバーを選んで入れる (modules.list)"
MODS="$B/kernel-pkg/lib/modules/$KVER"
depmod -b "$B/kernel-pkg" "$KVER"
grep -vE '^\s*(#|$)' "$HERE/modules.list" | while read -r m; do
  modprobe -d "$B/kernel-pkg" -S "$KVER" --show-depends "$m" 2>/dev/null | awk '$1=="insmod" {print $2}'
done | sort -u | while read -r ko; do
  rel=${ko#"$B/kernel-pkg/"}
  mkdir -p "$ROOT/$(dirname "$rel")"
  case "$ko" in
    *.zst) zstd -q -d -f "$ko" -o "$ROOT/${rel%.zst}" ;;   # BusyBox の modprobe は圧縮されたものを読めない
    *.xz)  xz -d -c "$ko" > "$ROOT/${rel%.xz}" ;;
    *)     cp "$ko" "$ROOT/$rel" ;;
  esac
done
cp "$MODS"/modules.order "$MODS"/modules.builtin* "$ROOT/lib/modules/$KVER/" 2>/dev/null || true
depmod -b "$ROOT" "$KVER"
grep -vE '^\s*(#|$)' "$HERE/modules.list" > "$ROOT/etc/modules"
echo "  $(find "$ROOT/lib/modules" -name '*.ko' | wc -l) 個のモジュール"

echo "WasabiOS Scratch $WASABI_VERSION ($WASABI_CODENAME)" > "$ROOT/etc/wasabios-release"
cat > "$ROOT/etc/os-release" <<REL
NAME="WasabiOS Scratch"
ID=wasabios
VERSION_ID="$WASABI_VERSION"
VERSION="$WASABI_VERSION ($WASABI_CODENAME)"
VERSION_CODENAME=$WASABI_CODENAME
PRETTY_NAME="WasabiOS Scratch $WASABI_VERSION ($WASABI_CODENAME)"
HOME_URL="https://github.com/wasabi-wa619/os"
REL

(cd "$ROOT" && find . -print0 | sort -z | cpio --null -o -H newc -R 0:0 --quiet) | gzip -9 > "$B/initramfs.gz"

# ---- 6. 起動 ISO ----------------------------------------------------------
log "起動 ISO を作成"
rm -rf "$B/iso"
mkdir -p "$B/iso/boot/grub"
cp "$KERNEL" "$B/iso/boot/vmlinuz"
cp "$B/initramfs.gz" "$B/iso/boot/initramfs.gz"
cat > "$B/iso/boot/grub/grub.cfg" <<'CFG'
set timeout=3
insmod all_video
# loglevel=5: 重要なメッセージだけ出す。4 以下 (quiet) にするとカーネルが起動ロゴを出さなくなる
menuentry "WasabiOS Scratch" {
    linux  /boot/vmlinuz loglevel=5
    initrd /boot/initramfs.gz
}
menuentry "WasabiOS Scratch (verbose boot)" {
    linux  /boot/vmlinuz
    initrd /boot/initramfs.gz
}
menuentry "WasabiOS Scratch (serial console)" {
    linux  /boot/vmlinuz console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.gz
}
CFG
grub-mkrescue -o "$ISO" "$B/iso" -- -volid WASABIOS_SCRATCH 2>/dev/null

log "完成!"
printf '  カーネル    %s\n' "$(du -h "$KERNEL" | cut -f1)"
printf '  initramfs   %s\n' "$(du -h "$B/initramfs.gz" | cut -f1)"
printf '  ISO         %s  %s\n' "$(du -h "$ISO" | cut -f1)" "$ISO"
echo "試す: make -C scratch run"
