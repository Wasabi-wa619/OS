#!/usr/bin/env bash
# 独自OSのライブISOをビルドするメインスクリプト
#   使い方: sudo ./scripts/build.sh
# 流れ: debootstrap でUbuntuの最小システムを作る
#      → chroot内で hooks/*.sh を順番に実行してカスタマイズ
#      → overlay/ のファイルを上書きコピー
#      → squashfs に圧縮して GRUB(BIOS+UEFI) で起動できるISOにする
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/os.conf
source "$ROOT_DIR/config/os.conf"

WORK="${WORK:-$ROOT_DIR/build}"
CHROOT="$WORK/chroot"
IMAGE="$WORK/image"
OUT="$ROOT_DIR/out"
ISO="$OUT/${OS_ID}-${OS_VERSION}-${ARCH}.iso"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "root で実行してください: sudo $0" >&2; exit 1; }
for cmd in debootstrap mksquashfs grub-mkrescue xorriso; do
  command -v "$cmd" >/dev/null || { echo "$cmd がありません。'make deps' を実行してください" >&2; exit 1; }
done

unmount_chroot() {
  for m in run dev/pts dev sys proc; do
    mountpoint -q "$CHROOT/$m" && umount -lf "$CHROOT/$m" || true
  done
}
trap unmount_chroot EXIT

# ---- 1. ベースシステム ---------------------------------------------------
if [[ ! -f "$CHROOT/.debootstrap-done" ]]; then
  log "debootstrap: Ubuntu $BASE_SUITE ($ARCH) を展開"
  rm -rf "$CHROOT"
  mkdir -p "$CHROOT"
  debootstrap --arch="$ARCH" --components=main,universe "$BASE_SUITE" "$CHROOT" "$BASE_MIRROR"
  touch "$CHROOT/.debootstrap-done"
else
  log "既存の debootstrap 結果を再利用 (やり直すなら 'make clean')"
fi

# ---- 2. chroot 内でカスタマイズ -----------------------------------------
log "chroot をマウント"
mount --bind /dev "$CHROOT/dev"
mount -t devpts devpts "$CHROOT/dev/pts"
mount -t proc proc "$CHROOT/proc"
mount -t sysfs sysfs "$CHROOT/sys"
mount -t tmpfs tmpfs "$CHROOT/run"
# chroot 内からネットに繋がるように (Ubuntu では resolv.conf がリンクなので置き換える)
rm -f "$CHROOT/etc/resolv.conf"
cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

# ビルド中にサービスが起動しないようにする
printf '#!/bin/sh\nexit 101\n' > "$CHROOT/usr/sbin/policy-rc.d"
chmod +x "$CHROOT/usr/sbin/policy-rc.d"

# 設定・パッケージリスト・フックを chroot に渡す
rm -rf "$CHROOT/tmp/build"
mkdir -p "$CHROOT/tmp/build"
cp -r "$ROOT_DIR/config" "$ROOT_DIR/hooks" "$CHROOT/tmp/build/"

for hook in "$ROOT_DIR"/hooks/*.sh; do
  name="$(basename "$hook")"
  log "hook: $name"
  chroot "$CHROOT" /usr/bin/env -i \
    HOME=/root PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 DESKTOP="$DESKTOP" BROWSER="$BROWSER" \
    /bin/bash -e "/tmp/build/hooks/$name"
done

log "overlay/ を適用"
cp -a "$ROOT_DIR/overlay/." "$CHROOT/"

# 後片付け (ISOに不要なもの)
rm -rf "$CHROOT/tmp/build" "$CHROOT/usr/sbin/policy-rc.d"
ln -sf ../run/systemd/resolve/stub-resolv.conf "$CHROOT/etc/resolv.conf"
unmount_chroot

# ---- 3. ISO イメージの作成 -----------------------------------------------
log "ISO の中身を作成"
rm -rf "$IMAGE"
mkdir -p "$IMAGE/casper" "$IMAGE/boot/grub" "$IMAGE/.disk" "$OUT"

cp "$(ls -1 "$CHROOT"/boot/vmlinuz-* | sort -V | tail -1)" "$IMAGE/casper/vmlinuz"
cp "$(ls -1 "$CHROOT"/boot/initrd.img-* | sort -V | tail -1)" "$IMAGE/casper/initrd"

chroot "$CHROOT" dpkg-query -W --showformat='${Package} ${Version}\n' > "$IMAGE/casper/filesystem.manifest"
du -sx --block-size=1 "$CHROOT" | cut -f1 > "$IMAGE/casper/filesystem.size"
echo "$OS_NAME $OS_VERSION \"$OS_CODENAME\" - $ARCH ($(date +%Y%m%d))" > "$IMAGE/.disk/info"

log "squashfs に圧縮 (数分かかります)"
mksquashfs "$CHROOT" "$IMAGE/casper/filesystem.squashfs" \
  -noappend -comp xz -e boot/grub -e .debootstrap-done

sed -e "s/@OS_NAME@/$OS_NAME/g" "$ROOT_DIR/config/grub.cfg" > "$IMAGE/boot/grub/grub.cfg"

log "ISO を作成: $ISO"
grub-mkrescue -o "$ISO" "$IMAGE" -- -volid "${OS_ID^^}_${OS_VERSION//./_}"

log "完成! $(du -h "$ISO" | cut -f1)  $ISO"
echo "QEMU で試す: make run"
