# Firefox (deb版) を Mozilla 公式リポジトリから入れる。CUI構成ではスキップ。
source /tmp/build/config/os.conf
[ "$DESKTOP" = "none" ] && exit 0

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
