# APT リポジトリの設定 (chroot 内で実行される)
source /tmp/build/config/os.conf

cat > /etc/apt/sources.list <<SRC
deb $BASE_MIRROR $BASE_SUITE main restricted universe multiverse
deb $BASE_MIRROR $BASE_SUITE-updates main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $BASE_SUITE-security main restricted universe multiverse
SRC

# snap はchroot内で動かないので使わない (Firefox は 20-firefox.sh で deb 版を入れる)
cat > /etc/apt/preferences.d/no-snap <<'PIN'
Package: snapd
Pin: release *
Pin-Priority: -10
PIN

apt-get update
apt-get -y upgrade
