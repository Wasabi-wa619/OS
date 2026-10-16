# 言語・タイムゾーン
source /tmp/build/config/os.conf

locale-gen "$LOCALE" en_US.UTF-8
update-locale LANG="$LOCALE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

# GNOME の入力: キーボード配列 (KEYMAP) と日本語入力 (Mozc)。Super+Space で切り替え
if [ -d /usr/share/glib-2.0/schemas ] && [ "$DESKTOP" != none ]; then
  cat > /usr/share/glib-2.0/schemas/92_wasabios-input.gschema.override <<OVR
[org.gnome.desktop.input-sources]
sources = [('xkb', '$KEYMAP'), ('ibus', 'mozc-jp')]
OVR
  glib-compile-schemas /usr/share/glib-2.0/schemas
fi
