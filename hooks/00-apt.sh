# APT リポジトリの設定 (chroot 内で実行される)
source /tmp/build/config/os.conf

cat > /etc/apt/sources.list <<SRC
deb $BASE_MIRROR $BASE_SUITE main restricted universe multiverse
deb $BASE_MIRROR $BASE_SUITE-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $BASE_SUITE-security main restricted universe multiverse
SRC

# Ubuntu の firefox / thunderbird は snap 版を入れるためのダミーで、chroot 内では入らない。
# Ubuntu 版は使わないようにする (Firefox は 05-firefox.sh で Mozilla 公式の deb 版を入れる)。
# snap 自体 (snapd) は普通に使えるので、起動後に snap のアプリも入れられる。
cat > /etc/apt/preferences.d/no-snap-transitional <<'PIN'
Package: firefox* thunderbird*
Pin: release o=Ubuntu
Pin-Priority: -1
PIN

apt-get update
apt-get -y upgrade
