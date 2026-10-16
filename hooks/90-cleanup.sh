# initramfs を作り直して(casper を含める)、キャッシュを掃除
update-initramfs -u -k all
apt-get -y autoremove --purge
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/*.bin /var/log/*.log /root/.bash_history
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
