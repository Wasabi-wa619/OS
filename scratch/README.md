# WasabiOS Scratch — ゼロから組み立てる WasabiOS

Ubuntu も Debian も使わず、**Linux カーネルを自分でビルドし、最初に動くプログラム (init) も自作して**
起動する OS です。いまは第1段階で、メモリ上だけで動く小さな OS (ISO で十数 MB) になっています。

```
電源 ON
 └─ GRUB (起動メニュー)
     └─ Linux カーネル 6.17   … 本家のソースを自分でビルド。起動ロゴはわさび
         └─ wasabi-init (PID 1) … 自作 (init/wasabi-init.c)
             ├─ /etc/rc.d/*     … 起動スクリプト (ネットワークなど)
             └─ シェル (tty1〜3) … BusyBox の sh。ls / vi / ip など 300 以上のコマンド
```

## 中身

| 部品 | どこ | 自作? |
|---|---|---|
| カーネル | `versions.conf` のソース + `kernel/wasabi.config` | ビルドと設定は自前 (MacBook 2012 向け) |
| 起動ロゴ | `kernel/logo_linux_clut224.ppm` | 自作 (ペンギンの代わりにわさび) |
| init (PID 1) | `init/wasabi-init.c` | **自作** (C 言語、約 270 行) |
| 基本コマンド | BusyBox (`busybox/wasabi.config`) | 借り物 (将来少しずつ自作に置き換えられる) |
| 設定ファイル・起動スクリプト | `rootfs/` | 自作 |
| `wasabi` コマンド | `rootfs/usr/bin/wasabi` | 自作 |

### wasabi-init がやっていること
1. `/proc` `/sys` `/dev` などをマウント
2. ホスト名を設定し、`/etc/rc.d/` の起動スクリプトを番号順に実行
3. tty1〜tty3 (Alt+F1〜F3) とシリアルでシェルを起動。閉じたら起動し直す
4. 親のいなくなったプロセス (ゾンビ) の回収
5. `poweroff` / `reboot` の合図を受けて、全プロセスを止めて電源を切る

## ビルドと実行

Ubuntu (MacBook の Ubuntu でも OK) で:

```bash
cd scratch
make deps        # 必要な道具を入れる (初回のみ)
make             # → ../out/wasabios-scratch-0.1-x86_64.iso  (初回は 10〜30 分)
make run         # QEMU で起動 (画面あり)
make run-serial  # ターミナルの中で起動 (Ctrl+A → X で終了)
```

USB に書き込んで MacBook で起動する方法は、上の階層の README の「Chromebook で USB に書き込む」「MacBook で USB から起動する」と同じです。

## 今できないこと (= これから作るもの)

- **日本語表示**: Linux の素のコンソールは日本語の文字を持っていないので、画面の表示は英語
- **保存**: 全部メモリ上で動くので、電源を切ると消える
- **Wi-Fi**: MacBook の Broadcom 製 Wi-Fi はファームウェアが必要 (有線 LAN は動く予定)
- **GUI**: まだ文字の画面だけ

## これからのロードマップ (案)

1. **ディスクにインストール**: SSD のパーティションに入れて、保存できるようにする
2. **自作パッケージマネージャー**: `wpkg install xxx` でソフトを追加できるようにする
3. **コンパイラーを載せる**: OS の中で C のプログラムを作れるようにする (自分自身をビルドできる OS へ)
4. **日本語と GUI**: フレームバッファで日本語表示 → Wayland などでウィンドウを出す
5. **BusyBox を自作コマンドに置き換えていく**
