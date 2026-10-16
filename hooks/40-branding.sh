# ライブ環境の名前まわり。
# OS 名 (os-release)・ロゴ・壁紙・起動画面は 15-wasabios.sh で入れたパッケージが担当する。
source /tmp/build/config/os.conf

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

# 文字だけの起動画面 (グラフィックが使えないとき) のタイトル
for f in /usr/share/plymouth/themes/*/*.plymouth; do
  [ -f "$f" ] && sed -i "s/^title=.*/title=$OS_NAME $OS_VERSION/" "$f"
done
