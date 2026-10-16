# ライブ USB 用の設定 (インストーラーがインストール時に取り除く)
#   - パスワードなしのユーザーで自動ログイン
#   - Dock に「WasabiOS をインストール」
source /tmp/build/config/os.conf

id "$LIVE_USER" >/dev/null 2>&1 || \
  useradd -m -s /bin/bash -c "$OS_NAME Live" -G sudo,adm,audio,video,plugdev "$LIVE_USER"
passwd -d "$LIVE_USER"
echo "$LIVE_USER" > /etc/wasabios/live-user
echo "$LIVE_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/wasabios-live
chmod 440 /etc/sudoers.d/wasabios-live

if [ -d /etc/gdm3 ]; then
  sed -i '/^AutomaticLogin/d' /etc/gdm3/custom.conf
  sed -i "s/^\[daemon\]/[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$LIVE_USER/" /etc/gdm3/custom.conf
  cat > /usr/share/glib-2.0/schemas/95_wasabios-live.gschema.override <<'OVR'
[org.gnome.shell:ubuntu]
favorite-apps = ['wasabi-install.desktop', 'firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'gparted.desktop']

[org.gnome.shell]
favorite-apps = ['wasabi-install.desktop', 'firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'gparted.desktop']

# ライブ USB では画面ロックしない
[org.gnome.desktop.screensaver]
lock-enabled = false
OVR
  glib-compile-schemas /usr/share/glib-2.0/schemas
fi

# GNOME の初回セットアップ画面は出さない (ライブでは不要、インストール時はインストーラーが名前などを聞く)
mkdir -p "/home/$LIVE_USER/.config"
touch "/home/$LIVE_USER/.config/gnome-initial-setup-done"
chown -R "$LIVE_USER:$LIVE_USER" "/home/$LIVE_USER/.config"
