# Firefox (deb版) を Mozilla 公式リポジトリから入れる。CUI構成ではスキップ。
# Ubuntu の firefox パッケージは snap 版への置き換えで chroot では入らないため、
# 10-packages より前に Mozilla のリポジトリを優先させておく。
source /tmp/build/config/os.conf
if [ "$DESKTOP" = "none" ] || [ "$BROWSER" != "firefox" ]; then exit 0; fi

apt-get install -y curl ca-certificates

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/packages.mozilla.org.asc
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  > /etc/apt/sources.list.d/mozilla.list
cat > /etc/apt/preferences.d/mozilla <<'PIN'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
PIN

apt-get update
apt-get install -y firefox firefox-l10n-ja
