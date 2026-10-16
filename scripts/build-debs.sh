#!/usr/bin/env bash
# packages/ 以下の独自パッケージを .deb にする (root 不要・数秒で終わる)
#   使い方: ./scripts/build-debs.sh                 → 全部 out/debs/*.deb
#           ./scripts/build-debs.sh wasabios-base   → 指定したものだけ
#   wasabios-boot は自作 init と BusyBox をコンパイルして入れる (scratch/build.sh --tools-only)
set -euo pipefail

command -v rsvg-convert >/dev/null || { echo "rsvg-convert がありません: sudo apt install librsvg2-bin" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config/os.conf"

# パッケージの版数: os.conf の OS_VERSION + ビルド日時 (例 0.1+202610161620)。
# 作り直すたびに新しい版になるので、apt が必ず新しいほうを入れる
DEB_VERSION="${DEB_VERSION:-$OS_VERSION+$(date -u +%Y%m%d%H%M)}"

STAGE="$ROOT_DIR/build/debs"
OUT="$ROOT_DIR/out/debs"
mkdir -p "$STAGE" "$OUT"

if [ $# -gt 0 ]; then names=("$@"); else names=(); for d in "$ROOT_DIR"/packages/*/; do names+=("$(basename "$d")"); done; fi

for name in "${names[@]}"; do
  src="$ROOT_DIR/packages/$name"
  [ -d "$src" ] || { echo "そのパッケージはありません: $name" >&2; exit 1; }
  dst="$STAGE/$name"
  rm -rf "$dst"
  rm -f "$OUT/${name}"_*.deb
  cp -a "$src" "$dst"

  sed -e "s|@VERSION@|$DEB_VERSION|g" -e "s|@MINVERSION@|$OS_VERSION|g" \
      -e "s|@OS_NAME@|$OS_NAME|g" \
      -e "s|@MAINTAINER@|$OS_MAINTAINER|g" \
      "$dst/DEBIAN/control.in" > "$dst/DEBIAN/control"
  rm "$dst/DEBIAN/control.in"

  # OS の名前やバージョンを os.conf から埋め込む
  if [ "$name" = wasabios-base ]; then
    mkdir -p "$dst/etc/wasabios"
    cat > "$dst/etc/wasabios/release" <<REL
WASABIOS_NAME="$OS_NAME"
WASABIOS_ID="$OS_ID"
WASABIOS_VERSION="$OS_VERSION"
WASABIOS_CODENAME="$OS_CODENAME"
REL
  fi

  # artwork/ のロゴ・壁紙をパッケージに入れる (元データは artwork/ だけに置く)
  case "$name" in
    wasabios-base)
      install -Dm644 "$ROOT_DIR/artwork/logo.svg" "$dst/usr/share/pixmaps/wasabios-logo.svg"
      install -Dm644 "$ROOT_DIR/artwork/logo.svg" "$dst/usr/share/icons/hicolor/scalable/apps/wasabios-logo.svg"
      ;;
    wasabios-desktop)
      install -Dm644 "$ROOT_DIR/artwork/wallpaper.svg" "$dst/usr/share/backgrounds/wasabios/wasabios-default.svg"
      rsvg-convert "$ROOT_DIR/artwork/watermark.svg" -o "$dst/usr/share/plymouth/themes/wasabios/watermark.png"
      install -d "$dst/usr/share/wasabios"
      rsvg-convert -h 96 "$ROOT_DIR/artwork/watermark.svg" -o "$dst/usr/share/wasabios/login-logo.png"
      ;;
    wasabios-boot)
      # 自作 init (scratch/init/) と BusyBox を静的リンクでビルドして入れる
      tools="$ROOT_DIR/scratch/build/tools"
      if [ ! -x "$tools/wasabi-init" ] || [ ! -x "$tools/busybox" ] \
         || [ -n "$(find "$ROOT_DIR/scratch/init" -newer "$tools/wasabi-init" -type f)" ]; then
        bash "$ROOT_DIR/scratch/build.sh" --tools-only
      fi
      install -Dm755 "$tools/wasabi-init" "$dst/usr/lib/wasabios/initramfs/init"
      install -Dm755 "$tools/busybox" "$dst/usr/lib/wasabios/initramfs/busybox"
      ;;
  esac

  # パーミッションを揃える (git では保存されないことがあるため)
  find "$dst" -type d -exec chmod 755 {} +
  find "$dst" -type f -exec chmod 644 {} +
  find "$dst/DEBIAN" -type f \( -name preinst -o -name postinst -o -name prerm -o -name postrm \) -exec chmod 755 {} +
  for x in "$dst"/usr/bin/* "$dst"/usr/sbin/* "$dst"/usr/lib/wasabios/* "$dst"/usr/lib/wasabios/initramfs/* \
           "$dst"/etc/update-motd.d/* "$dst"/etc/kernel/*.d/*; do
    [ -f "$x" ] && chmod 755 "$x"
  done

  arch=$(awk '/^Architecture:/ {print $2}' "$dst/DEBIAN/control")
  dpkg-deb --root-owner-group -Zxz --build "$dst" "$OUT/${name}_${DEB_VERSION}_${arch}.deb" >/dev/null
  echo "built: out/debs/${name}_${DEB_VERSION}_${arch}.deb"
done
