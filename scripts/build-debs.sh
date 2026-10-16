#!/usr/bin/env bash
# packages/ 以下の独自パッケージを .deb にする (root 不要・数秒で終わる)
#   使い方: ./scripts/build-debs.sh   → out/debs/*.deb
set -euo pipefail

command -v rsvg-convert >/dev/null || { echo "rsvg-convert がありません: sudo apt install librsvg2-bin" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/config/os.conf"

STAGE="$ROOT_DIR/build/debs"
OUT="$ROOT_DIR/out/debs"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE" "$OUT"

for src in "$ROOT_DIR"/packages/*/; do
  name="$(basename "$src")"
  dst="$STAGE/$name"
  cp -a "$src" "$dst"

  sed -e "s|@VERSION@|$OS_VERSION|g" \
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
      ;;
  esac

  # パーミッションを揃える (git では保存されないことがあるため)
  find "$dst" -type d -exec chmod 755 {} +
  find "$dst" -type f -exec chmod 644 {} +
  find "$dst/DEBIAN" -type f \( -name preinst -o -name postinst -o -name prerm -o -name postrm \) -exec chmod 755 {} +
  for x in "$dst"/usr/bin/* "$dst"/usr/lib/wasabios/* "$dst"/etc/update-motd.d/*; do
    [ -f "$x" ] && chmod 755 "$x"
  done

  dpkg-deb --root-owner-group -Zxz --build "$dst" "$OUT/${name}_${OS_VERSION}_all.deb" >/dev/null
  echo "built: out/debs/${name}_${OS_VERSION}_all.deb"
done
