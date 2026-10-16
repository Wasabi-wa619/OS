# MacBook 向けドライバー (MAC_SUPPORT=yes のとき)
# Broadcom の Wi-Fi ドライバー (bcmwl) は DKMS で WasabiOS カーネル向けにその場でビルドされる。
# カーネルが新しすぎてビルドできなかった場合も ISO 作りは止めず、警告だけ出す。
source /tmp/build/config/os.conf
[ "$MAC_SUPPORT" = yes ] || exit 0

grep -vE '^\s*(#|$)' /tmp/build/config/packages/mac.list | while read -r pkg; do
  if apt-get install -y "$pkg"; then
    echo "OK: $pkg"
  else
    echo "!! 警告: $pkg を入れられませんでした (WasabiOS カーネル向けにビルドできない可能性)" >&2
    apt-get purge -y "$pkg" || dpkg --purge --force-all "$pkg" || true
  fi
done

# Wi-Fi ドライバーが実際にできたか表示しておく
ls /lib/modules/*/updates/dkms/ 2>/dev/null || echo "!! 警告: DKMS でビルドされたドライバーはありません" >&2
exit 0
