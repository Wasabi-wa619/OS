# ライブ環境の名前まわり。
# OS 名 (os-release)・ロゴ・壁紙・起動画面は 15-wasabios.sh で入れたパッケージが担当する。
source /tmp/build/config/os.conf

echo "$OS_HOSTNAME" > /etc/hostname

# Ubuntu のログインメッセージ(広告など)を無効化
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true


# 文字だけの起動画面 (グラフィックが使えないとき) のタイトル
for f in /usr/share/plymouth/themes/*/*.plymouth; do
  [ -f "$f" ] && sed -i "s/^title=.*/title=$OS_NAME $OS_VERSION/" "$f"
done
