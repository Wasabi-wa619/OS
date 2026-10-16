#!/usr/bin/env python3
"""QEMU を起動し、シリアルコンソール越しにコマンドを打って結果を確かめるテスト用スクリプト。

使い方:
  tests/qemu-serial.py [--disk disk.img] [--iso x.iso] [--append "カーネル引数"] [--timeout 秒] \
                       --expect "ログイン可能になったら出る文字列" -- 'コマンド1' 'コマンド2' ...
--iso と --append を両方指定すると、ISO の中の /boot/vmlinuz と initrd.img を直接起動する
(GRUB を通さずにカーネル引数を変えられる)。ログは標準出力に全部出す。
"""
import argparse, os, select, subprocess, sys, tempfile, time

ap = argparse.ArgumentParser()
ap.add_argument("--iso"); ap.add_argument("--disk"); ap.add_argument("--append")
ap.add_argument("--initrd", help="ISO の initrd.img の代わりに使う (init を作り直したときの確認用)")
ap.add_argument("--uefi", action="store_true"); ap.add_argument("--mem", default="3072")
ap.add_argument("--timeout", type=int, default=900)
ap.add_argument("--expect", required=True, help="この文字列が出たら起動完了とみなす")
ap.add_argument("--prompt", default="# ", help="コマンドの終わりを判定する文字列")
ap.add_argument("cmds", nargs="*")
a = ap.parse_args()

cmd = ["qemu-system-x86_64", "-m", a.mem, "-smp", "2", "-nographic", "-no-reboot",
       "-netdev", "user,id=n0", "-device", "e1000,netdev=n0"]
if os.path.exists("/dev/kvm"): cmd += ["-enable-kvm", "-cpu", "host"]
if a.uefi: cmd += ["-bios", "/usr/share/ovmf/OVMF.fd"]
if a.disk: cmd += ["-drive", f"file={a.disk},format=raw,if=virtio"]
if a.iso:
    cmd += ["-drive", f"file={a.iso},media=cdrom,readonly=on"]
    if a.append:
        tmp = tempfile.mkdtemp()
        for f in ("vmlinuz", "initrd.img"):
            subprocess.run(["xorriso", "-osirrox", "on", "-indev", a.iso, "-extract", f"/boot/{f}", f"{tmp}/{f}"],
                           check=True, capture_output=True)
        cmd += ["-kernel", f"{tmp}/vmlinuz", "-initrd", a.initrd or f"{tmp}/initrd.img", "-append", a.append]
    else:
        cmd += ["-boot", "d"]
else:
    cmd += ["-boot", "c"]

p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
buf = b""
def pump(token, timeout):
    global buf
    end = time.time() + timeout
    start = len(buf)
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if r:
            d = os.read(p.stdout.fileno(), 65536)
            if not d: return False
            buf += d
            sys.stdout.write(d.decode("utf-8", "replace")); sys.stdout.flush()
            if token.encode() in buf[start:]: return True
        if p.poll() is not None: return False
    return False

t0 = time.time()
ok = pump(a.expect, a.timeout)
print(f"\n### boot {'OK' if ok else 'FAILED'} after {time.time()-t0:.0f}s", flush=True)
if ok:
    for c in a.cmds:
        time.sleep(1)
        p.stdin.write((c + "\n").encode()); p.stdin.flush()
        pump(a.prompt, 1800 if "wasabi-install" in c else 120)
p.kill()
sys.exit(0 if ok else 1)
