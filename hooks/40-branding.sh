# OS の名前を書き換える (ここが「独自OS」になる部分)
source /tmp/build/config/os.conf
. /etc/os-release   # ベースの Ubuntu のコードネームを使うため読み込む

# dpkg-divert: apt upgrade で base-files が更新されても上書きされないようにする
for f in /usr/lib/os-release /etc/lsb-release /etc/issue /etc/issue.net; do
  dpkg-divert --local --rename --add "$f"
done
ln -sf ../usr/lib/os-release /etc/os-release

cat > /usr/lib/os-release <<REL
PRETTY_NAME="$OS_NAME $OS_VERSION"
NAME="$OS_NAME"
VERSION_ID="$OS_VERSION"
VERSION="$OS_VERSION ($OS_CODENAME)"
VERSION_CODENAME=$OS_CODENAME
ID=$OS_ID
ID_LIKE="ubuntu debian"
UBUNTU_CODENAME=$UBUNTU_CODENAME
HOME_URL="https://github.com/wasabi-wa619/os"
REL
cat > /etc/lsb-release <<REL
DISTRIB_ID=$OS_NAME
DISTRIB_RELEASE=$OS_VERSION
DISTRIB_CODENAME=$OS_CODENAME
DISTRIB_DESCRIPTION="$OS_NAME $OS_VERSION"
REL

echo "$OS_NAME $OS_VERSION \\n \\l" > /etc/issue
echo "$OS_NAME $OS_VERSION" > /etc/issue.net
echo "$OS_HOSTNAME" > /etc/hostname

# Ubuntu のログインメッセージ(広告など)を無効化
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true

# ライブ環境の設定 (casper が起動時に読む)
cat > /etc/casper.conf <<CONF
export USERNAME="$LIVE_USER"
export USERFULLNAME="$OS_NAME Live"
export HOST="$OS_HOSTNAME"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="$OS_NAME"
CONF

# 起動時のスプラッシュ画面 (Plymouth) のタイトル
for f in /usr/share/plymouth/themes/*/*.plymouth; do
  [ -f "$f" ] && sed -i "s/^title=.*/title=$OS_NAME $OS_VERSION/" "$f"
done
