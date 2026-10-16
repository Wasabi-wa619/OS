# WasabiOS Scratch (ゼロから組み立てる版)
#   make deps   必要な道具を入れる (Ubuntu / Debian で。初回のみ)
#   make        ISO を作る → ../out/wasabios-scratch-*.iso
#   make run    QEMU で起動 (画面あり)
#   make run-serial  QEMU で起動 (ターミナルの中で)
#   make clean  ビルド結果を消す (ダウンロードしたソースは残す)
.PHONY: all deps run run-serial run-uefi clean distclean

ISO = $(firstword $(wildcard ../out/wasabios-scratch-*.iso))
KVM = $(if $(wildcard /dev/kvm),-enable-kvm,)

all:
	bash ./build.sh

deps:
	sudo apt-get update
	sudo apt-get install -y build-essential bc flex bison libelf-dev libssl-dev libdw-dev gawk rsync kmod dpkg-dev zstd debhelper \
		cpio curl xorriso mtools grub-common grub-pc-bin grub-efi-amd64-bin \
		qemu-system-x86 ovmf

run:
	qemu-system-x86_64 $(KVM) -m 1024 -cdrom $(ISO) -boot d -vga std \
		-netdev user,id=n0 -device e1000,netdev=n0

run-uefi:
	qemu-system-x86_64 $(KVM) -m 1024 -cdrom $(ISO) -boot d -vga std \
		-bios /usr/share/ovmf/OVMF.fd -netdev user,id=n0 -device e1000,netdev=n0

# GRUB を通さず直接カーネルを起動し、ターミナルを画面代わりにする (Ctrl+A → X で終了)
run-serial:
	qemu-system-x86_64 $(KVM) -m 1024 -nographic -no-reboot \
		-kernel build/iso/boot/vmlinuz -initrd build/iso/boot/initramfs.gz \
		-append "console=ttyS0,115200" -netdev user,id=n0 -device e1000,netdev=n0

clean:
	rm -rf build/linux-* build/busybox-* build/init build/rootfs build/iso build/initramfs.gz

distclean:
	rm -rf build
