# よく使うコマンドのまとめ
.PHONY: deps deb install uninstall iso run run-uefi clean

DESKTOP ?= $(shell . ./config/os.conf && echo $$DESKTOP)
BROWSER ?= $(shell . ./config/os.conf && echo $$BROWSER)
ISO = $(firstword $(wildcard out/*.iso))

## ビルドに必要なツールを入れる (Ubuntu/Debian ホスト)
deps:
	sudo apt-get update
	sudo apt-get install -y debootstrap squashfs-tools xorriso mtools librsvg2-bin \
		grub-common grub-pc-bin grub-efi-amd64-bin qemu-system-x86 ovmf

## 独自パッケージ (.deb) を作る → out/debs/
deb:
	bash ./scripts/build-debs.sh

## いま使っている Ubuntu に独自部分を入れる (MacBook 用)
install:
	bash ./scripts/install-on-ubuntu.sh

## 入れた独自部分を消して Ubuntu に戻す
uninstall:
	sudo apt-get purge -y 'wasabios-*'

## ISO をビルドする
iso:
	sudo DESKTOP=$(DESKTOP) BROWSER=$(BROWSER) bash ./scripts/build.sh

## QEMU で起動して試す (BIOS)
run:
	qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -cdrom $(ISO) -boot d -vga virtio

## QEMU で起動して試す (UEFI)
run-uefi:
	qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -cdrom $(ISO) -boot d -vga virtio \
		-bios /usr/share/ovmf/OVMF.fd

## ビルド結果を全部消して最初からやり直せるようにする
## (ビルドが途中で止まって /dev などがマウントされたままでも、本物の /dev を消さないように先に外す)
clean:
	sudo sh -c 'findmnt -rn -o TARGET | grep "^$(CURDIR)/build" | sort -r | xargs -r -n1 umount -lf'
	@if findmnt -rn -o TARGET | grep -q "^$(CURDIR)/build"; then echo "マウントが残っているので中止します" >&2; exit 1; fi
	sudo rm -rf --one-file-system build out
