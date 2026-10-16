# scratch/ — WasabiOS の自作部分

ここには WasabiOS のうち **自分で作っている部分** が入っています。

```
電源 ON
 └─ GRUB (起動メニュー)
     └─ WasabiOS カーネル        … kernel/  Linux 本家のソースを自分でビルド (ロゴはわさび)
         └─ wasabi-init (PID 1)   … init/    自作 (C 言語)
             ├─ フル版: USB / SSD から OS を見つけて systemd (Ubuntu) に引き継ぐ
             ├─ 失敗したとき: レスキュー用のシェル
             └─ シード版: これ自体が OS (BusyBox のコマンドだけで動く 30MB の小さい OS)
```

## カーネル (`kernel/`)

| ファイル | 中身 |
|---|---|
| `ubuntu-6.17.0-41-generic.config` | Ubuntu のカーネル設定そのまま (土台) |
| `wasabi.config` | その上に重ねる WasabiOS の設定 (名前・ロゴ・起動に必要なドライバーを本体に組み込む・使わないドライバーを外す) |
| `logo_linux_clut224.ppm` | 起動ロゴ (ペンギンの代わり) |
| `build-kernel.sh` | `.deb` パッケージとしてビルドする |

土台が Ubuntu と同じなので、snap / Docker / Wi-Fi / サウンドなど Ubuntu のアプリが前提にする機能はそのまま入っています。
`.deb` で作るので、DKMS (Wi-Fi などの追加ドライバー) もこのカーネル向けに自動でビルドされます
(MacBook の Broadcom Wi-Fi ドライバー `wl` で確認済み)。

```bash
make -C scratch deps                 # 必要な道具 (初回だけ)
bash scratch/kernel/build-kernel.sh  # → out/kernel/*.deb  (4 コアで 1〜2 時間)
```

> **注意: カーネルのセキュリティ更新は自分で行う必要があります。**
> Ubuntu のカーネルは Ubuntu が修正を配ってくれますが、WasabiOS カーネルは `versions.conf` に書いた
> バージョンのままです。新しいバージョンが出たら `versions.conf` の URL とチェックサムを書き換えて作り直してください。

## wasabi-init (`init/`)

| ファイル | 中身 |
|---|---|
| `wasabi-init.c` | PID 1 本体。マウント、起動ロゴ、シェルの起動と再起動、ゾンビ回収、電源オフ |
| `stage1.c` | 本物の OS を探して引き継ぐ部分 (ループデバイス、overlay、switch_root を自前で実装) |

カーネルのコマンドラインで動きが変わります:

| 引数 | 動き |
|---|---|
| `wasabi.live` | USB / DVD の中の `wasabios/root.squashfs` を探して読み込み専用でマウントし、書き込み用の層を重ねて起動 |
| `wasabi.toram` | ライブのとき、squashfs をメモリにコピーしてから起動 (USB を抜ける) |
| `root=UUID=...` | インストール済みのディスクから起動 |
| どちらも無し | この initramfs 自体を OS として動かす (シード版 / レスキュー) |

ライブ起動のとき、ラベルが `WASABI-DATA` の ext4 パーティションがあれば、変更をそこに保存します。

フル版では `wasabios-boot` パッケージの `wasabi-mkinitramfs` が、この init と BusyBox を initramfs に詰めます。
Ubuntu の `update-initramfs` はこれに置き換わるので、カーネルやパッケージを更新しても自作の initramfs が使われ続けます。

## シード版

自作 init + BusyBox + 必要なドライバーだけの小さい OS です (ISO で約 30MB)。

```bash
cd scratch
make             # → ../out/wasabios-scratch-0.1-x86_64.iso (カーネルが無ければ先にビルド)
make run         # QEMU で起動 (画面あり)
make run-serial  # ターミナルの中で起動 (Ctrl+A → X で終了)
```

- 入るドライバーは `modules.list` で選ぶ (有線 LAN、MacBook のセンサーなど)
- 設定ファイルと起動スクリプトは `rootfs/`、`wasabi` コマンドもここ
- 画面 (Linux コンソール) は日本語を表示できないので、表示は英語
