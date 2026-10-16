# 言語・タイムゾーン
source /tmp/build/config/os.conf

locale-gen "$LOCALE" en_US.UTF-8
update-locale LANG="$LOCALE"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone
