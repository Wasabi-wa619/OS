# WasabiOS カーネル (自前ビルド) と、自作 init 入りの起動パッケージを入れる。
# Ubuntu のカーネル (linux-generic) と casper の代わり。
# パッケージ (10-packages.sh) より先に入れるのは、Wi-Fi ドライバーなどの DKMS をこのカーネル向けにビルドさせるため。
source /tmp/build/config/os.conf

# ISO の中では GRUB は使わない (起動は ISO 側の GRUB)。インストーラーが入れる
WASABIOS_SKIP_GRUB=1 apt-get install -y \
  /tmp/build/debs/wasabios-base_*.deb \
  /tmp/build/debs/wasabios-boot_*.deb \
  /tmp/build/kernel/linux-image-*.deb \
  /tmp/build/kernel/linux-headers-*.deb
