#!/usr/bin/env bash
# いま使っている Ubuntu に WasabiOS の独自部分を入れる (再インストール不要・データはそのまま)
#   使い方: ./scripts/install-on-ubuntu.sh       (make install でも同じ)
#   元に戻す: sudo apt purge 'wasabios-*'        (make uninstall でも同じ)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. /etc/os-release
if [ "$ID" != ubuntu ]; then
  echo "Ubuntu (またはその派生) 専用です: $PRETTY_NAME" >&2
  exit 1
fi

# .deb を作るのに必要な道具
command -v rsvg-convert >/dev/null || sudo apt-get install -y librsvg2-bin
bash "$ROOT_DIR/scripts/build-debs.sh" wasabios-base wasabios-desktop wasabios-mac

pkgs=("$ROOT_DIR"/out/debs/wasabios-base_*.deb)
if dpkg -s gnome-shell >/dev/null 2>&1; then
  pkgs+=("$ROOT_DIR"/out/debs/wasabios-desktop_*.deb)
else
  echo "GNOME が見つからないので壁紙・テーマ (wasabios-desktop) は入れません"
fi
if grep -qi apple /sys/class/dmi/id/sys_vendor 2>/dev/null; then
  echo "Mac を検出: $(cat /sys/class/dmi/id/product_name) → wasabios-mac も入れます"
  pkgs+=("$ROOT_DIR"/out/debs/wasabios-mac_*.deb)
fi

sudo apt-get update
# --reinstall: バージョンを上げずに作り直したときも入れ直す
sudo apt-get install -y --reinstall "${pkgs[@]}"

cat <<MSG

完了! 再起動すると起動画面とログイン後の見た目が変わります。
  wasabi info    … 情報表示
  wasabi theme   … 壁紙を自分で変えていた場合、WasabiOS の見た目にする
  元に戻すとき   … sudo apt purge 'wasabios-*'
MSG
