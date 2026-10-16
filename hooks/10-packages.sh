# パッケージのインストール
source /tmp/build/config/os.conf

# キーボード設定などの質問に事前回答しておく
debconf-set-selections <<SEL
keyboard-configuration keyboard-configuration/layoutcode string $KEYMAP
keyboard-configuration keyboard-configuration/modelcode string pc105
tzdata tzdata/Areas select ${TIMEZONE%%/*}
tzdata tzdata/Zones/${TIMEZONE%%/*} select ${TIMEZONE#*/}
SEL

read_list() { [ -f "$1" ] && grep -vE '^\s*(#|$)' "$1" || true; }

PKGS=$( {
  read_list /tmp/build/config/packages/base.list
  read_list "/tmp/build/config/packages/$DESKTOP.list"
  read_list /tmp/build/config/packages/extra.list
} | sort -u )

echo "インストールするパッケージ:" $PKGS
# shellcheck disable=SC2086
apt-get install -y $PKGS
