#!/usr/bin/env bash
# WasabiOS カーネルを .deb パッケージとしてビルドする
#   使い方: bash scratch/kernel/build-kernel.sh   → out/kernel/linux-image-*.deb, linux-headers-*.deb
#
# 本家 Linux のソース + Ubuntu の設定 (土台) + wasabi.config (上乗せ) + わさびの起動ロゴ。
# .deb にしておくと、apt でインストールでき、DKMS (Wi-Fi などの追加ドライバー) もこのカーネル向けにビルドされる。
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
source "$HERE/versions.conf"

B="$HERE/build"
SRC="$B/src"
OUT="$HERE/../out/kernel"
LINUX_DIR="$B/linux-$LINUX_VERSION"
JOBS="${JOBS:-$(nproc)}"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
mkdir -p "$SRC" "$OUT"

file="$SRC/${LINUX_URL##*/}"
if [ ! -f "$file" ]; then
  log "ダウンロード: ${LINUX_URL##*/}"
  curl -fL --retry 3 -o "$file.part" "$LINUX_URL" && mv "$file.part" "$file"
fi
echo "$LINUX_SHA256  $file" | sha256sum -c --quiet
[ -d "$LINUX_DIR" ] || { log "ソースを展開"; tar -C "$B" -xf "$file"; }

log "設定: Ubuntu の設定 + wasabi.config"
cp "$HERE/kernel/logo_linux_clut224.ppm" "$LINUX_DIR/drivers/video/logo/logo_linux_clut224.ppm"
cp "$HERE/kernel/$UBUNTU_KERNEL_CONFIG" "$LINUX_DIR/.config"
"$LINUX_DIR/scripts/kconfig/merge_config.sh" -m -O "$LINUX_DIR" \
  "$LINUX_DIR/.config" "$HERE/kernel/wasabi.config" >/dev/null
make -C "$LINUX_DIR" -s olddefconfig
missing=0
while IFS= read -r line; do
  case "$line" in
    CONFIG_*=*|"# CONFIG_"*" is not set")
      grep -qx "$line" "$LINUX_DIR/.config" || { echo "  (注意) 反映できなかった設定: $line"; missing=1; } ;;
  esac
done < "$HERE/kernel/wasabi.config"

KVER="$(make -C "$LINUX_DIR" -s kernelrelease)"
log "Linux $KVER をビルド (Ubuntu と同じ数千のドライバー入り。4コアで 1〜2 時間)"
rm -f "$B"/linux-*.deb "$B"/linux-upstream* "$B"/*.buildinfo "$B"/*.changes
make -C "$LINUX_DIR" -j"$JOBS" bindeb-pkg \
  KDEB_PKGVERSION="$LINUX_VERSION.0-$WASABI_KERNEL_REV" \
  KBUILD_BUILD_USER=wasabi KBUILD_BUILD_HOST=wasabios >"$B/kernel-build.log" 2>&1 \
  || { tail -40 "$B/kernel-build.log"; echo "カーネルのビルドに失敗しました (全ログ: $B/kernel-build.log)" >&2; exit 1; }

rm -f "$OUT"/*.deb
mv "$B"/linux-image-"$KVER"_*.deb "$B"/linux-headers-"$KVER"_*.deb "$OUT"/
rm -f "$B"/linux-*.deb "$B"/*.buildinfo "$B"/*.changes
log "完成"
ls -la "$OUT"
