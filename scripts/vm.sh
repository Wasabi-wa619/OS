#!/usr/bin/env bash
# WasabiOS を仮想マシン (QEMU) で試す
#
#   bash scripts/vm.sh live    ISO (ライブ USB の代わり) から起動。仮想 SSD も付くので、インストールも試せる
#   bash scripts/vm.sh disk    仮想 SSD から起動 (インストールしたあと。USB を抜いた状態)
#   bash scripts/vm.sh seed    シード版 (小さい版) を起動
#   bash scripts/vm.sh reset   仮想 SSD と UEFI の設定を消して、まっさらに戻す
#
# 環境変数: ISO=ISOファイル  MEM=メモリ(MB, 既定 3072)  CPUS=CPU数(既定 2)  DISK_SIZE=仮想SSDの大きさ(既定 30G)
#           VM_DISPLAY=画面の出し方 (既定 gtk。テスト用に none も)  VM_EXTRA=QEMU に足す引数
#
# Mac と同じ UEFI で起動し、UEFI の設定 (起動ディスクの登録) も保存されるので、実機に近い動きになる。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VM="$ROOT_DIR/out/vm"
DISK="$VM/disk.img"
VARS="$VM/OVMF_VARS.fd"
MEM="${MEM:-3072}"
CPUS="${CPUS:-2}"
DISK_SIZE="${DISK_SIZE:-30G}"

die() { echo "✗ $*" >&2; exit 1; }

command -v qemu-system-x86_64 >/dev/null || die "QEMU がありません: sudo apt install qemu-system-x86 ovmf"

# UEFI のファームウェア (Ubuntu の ovmf パッケージ)
CODE=""
for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
  [ -f "$f" ] && { CODE="$f"; break; }
done
[ -n "$CODE" ] || die "UEFI のファームウェアがありません: sudo apt install ovmf"
VARS_TEMPLATE="${CODE/CODE/VARS}"

ACCEL=()
if [ -w /dev/kvm ]; then
  ACCEL=(-enable-kvm -cpu host)
else
  echo "! KVM が使えないので遅くなります (sudo usermod -aG kvm \$USER して再ログインすると使えるようになることがあります)"
fi

prepare() {
  mkdir -p "$VM"
  [ -f "$DISK" ] || { echo "仮想 SSD を作成: $DISK ($DISK_SIZE、実際に使った分だけ容量を使う)"; truncate -s "$DISK_SIZE" "$DISK"; }
  [ -f "$VARS" ] || cp "$VARS_TEMPLATE" "$VARS"
}

base() {
  qemu-system-x86_64 "${ACCEL[@]}" -m "$MEM" -smp "$CPUS" \
    -machine q35 \
    -drive if=pflash,format=raw,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,file="$VARS" \
    -vga virtio -display "${VM_DISPLAY:-gtk,zoom-to-fit=on}" ${VM_EXTRA:-} \
    -device qemu-xhci -device usb-tablet \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    "$@"
}

find_iso() { # ISO=... が無ければ out/ の中の最新のもの
  local pattern=$1
  if [ -n "${ISO:-}" ]; then echo "$ISO"; return; fi
  ls -t "$ROOT_DIR"/out/$pattern 2>/dev/null | head -1
}

case "${1:-live}" in
  live)
    iso=$(find_iso 'wasabios-[0-9]*.iso')
    [ -f "$iso" ] || die "ISO がありません。make iso で作るか、ISO=ダウンロードしたファイル を指定してください"
    prepare
    echo "起動: $iso (ライブ) + 仮想 SSD"
    base -drive file="$iso",media=cdrom,readonly=on,if=none,id=cd -device ide-cd,drive=cd,bootindex=0 \
         -drive file="$DISK",format=raw,if=none,id=hd -device virtio-blk-pci,drive=hd,bootindex=1
    ;;
  disk)
    [ -f "$DISK" ] || die "仮想 SSD がありません。先に vm.sh live でインストールしてください"
    prepare
    echo "起動: 仮想 SSD (インストール済みの WasabiOS)"
    base -drive file="$DISK",format=raw,if=none,id=hd -device virtio-blk-pci,drive=hd,bootindex=0
    ;;
  seed)
    iso=$(find_iso 'wasabios-scratch-*.iso')
    [ -f "$iso" ] || die "シード版の ISO がありません: make -C scratch"
    prepare
    base -drive file="$iso",media=cdrom,readonly=on,if=none,id=cd -device ide-cd,drive=cd,bootindex=0
    ;;
  reset)
    rm -f "$DISK" "$VARS"
    echo "仮想 SSD と UEFI の設定を消しました"
    ;;
  *)
    sed -n '2,10p' "$0"
    exit 1
    ;;
esac
