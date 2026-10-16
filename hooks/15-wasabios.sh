# WasabiOS の独自パッケージ (packages/ から作った .deb) を入れる。
# MacBook の Ubuntu に make install で入れるものと同じ。
source /tmp/build/config/os.conf

PKGS=(/tmp/build/debs/wasabios-base_*.deb /tmp/build/debs/wasabios-boot_*.deb /tmp/build/debs/wasabios-installer_*.deb)
[ "$DESKTOP" != none ] && PKGS+=(/tmp/build/debs/wasabios-desktop_*.deb)
[ "$MAC_SUPPORT" = yes ] && PKGS+=(/tmp/build/debs/wasabios-mac_*.deb)

# initramfs は 90-cleanup.sh で最後に1回だけ作る。GRUB はインストーラーが入れる
WASABIOS_SKIP_INITRAMFS=1 WASABIOS_SKIP_GRUB=1 apt-get install -y "${PKGS[@]}"
