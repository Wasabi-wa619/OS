# よく使うコマンドのまとめ
.PHONY: deps iso run run-uefi clean

DESKTOP ?= $(shell . ./config/os.conf && echo $$DESKTOP)
BROWSER ?= $(shell . ./config/os.conf && echo $$BROWSER)
ISO = $(firstword $(wildcard out/*.iso))

## ビルドに必要なツールを入れる (Ubuntu/Debian ホスト)
deps:
	sudo apt-get update
	sudo apt-get install -y debootstrap squashfs-tools xorriso mtools \
		grub-common grub-pc-bin grub-efi-amd64-bin qemu-system-x86 ovmf

## ISO をビルドする
iso:
	sudo DESKTOP=$(DESKTOP) BROWSER=$(BROWSER) ./scripts/build.sh

## QEMU で起動して試す (BIOS)
run:
	qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -cdrom $(ISO) -boot d -vga virtio

## QEMU で起動して試す (UEFI)
run-uefi:
	qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -cdrom $(ISO) -boot d -vga virtio \
		-bios /usr/share/ovmf/OVMF.fd

## ビルド結果を全部消して最初からやり直せるようにする
clean:
	sudo rm -rf build out
