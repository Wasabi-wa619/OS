# よく使うコマンドのまとめ
.PHONY: deps deb install uninstall iso vm vm-disk vm-seed vm-reset clean

DESKTOP ?= $(shell . ./config/os.conf && echo $$DESKTOP)
BROWSER ?= $(shell . ./config/os.conf && echo $$BROWSER)

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

## 仮想マシンで試す (scripts/vm.sh)。ISO=ダウンロードした.iso で別の ISO も使える
## ライブ USB の代わりに ISO から起動。仮想 SSD 付きなのでインストールも試せる
vm:
	bash ./scripts/vm.sh live

## インストールした仮想 SSD から起動
vm-disk:
	bash ./scripts/vm.sh disk

## シード版を起動
vm-seed:
	bash ./scripts/vm.sh seed

## 仮想 SSD を消して最初からやり直す
vm-reset:
	bash ./scripts/vm.sh reset

## ビルド結果を全部消して最初からやり直せるようにする
## (ビルドが途中で止まって /dev などがマウントされたままでも、本物の /dev を消さないように先に外す)
clean:
	sudo sh -c 'findmnt -rn -o TARGET | grep "^$(CURDIR)/build" | sort -r | xargs -r -n1 umount -lf'
	@if findmnt -rn -o TARGET | grep -q "^$(CURDIR)/build"; then echo "マウントが残っているので中止します" >&2; exit 1; fi
	sudo rm -rf --one-file-system build out
