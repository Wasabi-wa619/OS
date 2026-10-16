# WasabiOS

Ubuntu 24.04 LTS をベースにした自作 Linux ディストリビューションです。
Ubuntu 自体も Debian をベースにカスタマイズしたディストリビューションで、このリポジトリも同じやり方で
**Ubuntu をベースに名前・パッケージ・設定を変えた独自 OS のライブ ISO** を作ります。

USB メモリに書き込めば実機で起動でき、BIOS と UEFI の両方に対応しています。

## しくみ

```
debootstrap            Ubuntu の最小システムを build/chroot/ に展開
   ↓
hooks/*.sh             chroot 内で番号順に実行してカスタマイズ
   ↓                     00-apt       リポジトリ設定
   ↓                     10-packages  config/packages/*.list のパッケージを入れる
   ↓                     20-firefox   Firefox (deb版)
   ↓                     30-locale    日本語・タイムゾーン
   ↓                     40-branding  OS名を書き換え (os-release, 起動画面など)
   ↓                     90-cleanup   initramfs 再生成・掃除
overlay/               ここに置いたファイルがそのまま / に上書きコピーされる
   ↓
mksquashfs + GRUB      圧縮して起動可能な ISO (out/*.iso) にする
```

ライブ起動には Ubuntu と同じ `casper` を使っています。

## ビルド方法

### A. GitHub Actions でビルド (Linux マシンがなくてもOK)

1. GitHub のリポジトリページ → **Actions** → **Build ISO** → **Run workflow**
2. デスクトップ環境を選んで実行 (30〜60分程度)
3. 完了したら実行結果ページの **Artifacts** から ISO をダウンロード

`v0.1` のようなタグを push すると Releases にも自動で ISO が添付されます
(GitHub Releases は 1 ファイル 2GB までなので、大きいデスクトップ構成では Artifacts を使ってください)。

### B. 手元の Ubuntu / Debian でビルド

root 権限と 20GB 程度の空きディスク、ネット接続が必要です。WSL2 でも動きます。

```bash
make deps              # ビルドツールを入れる (初回のみ)
make iso               # ISO を作成 → out/wasabios-0.1-amd64.iso
make iso DESKTOP=none  # CUI だけの軽い版
make run               # QEMU で起動して試す (make run-uefi で UEFI)
make clean             # ビルド結果を消す
```

2回目以降は debootstrap の結果を再利用するので速くなります。

### 実機で使う

[balenaEtcher](https://etcher.balena.io/) や [Rufus](https://rufus.ie/)(DD モード) で ISO を USB メモリに書き込み、
そこから起動します。Linux なら `sudo dd if=out/wasabios-0.1-amd64.iso of=/dev/sdX bs=4M status=progress` でも可。
セキュアブートは OFF にしてください。

## カスタマイズ方法

| やりたいこと | 編集する場所 |
|---|---|
| OS の名前・バージョン・ユーザー名 | `config/os.conf` |
| デスクトップ環境の切り替え (xfce/gnome/kde/none) | `config/os.conf` の `DESKTOP` |
| アプリを追加 | `config/packages/extra.list` に1行1パッケージ |
| 設定ファイル・壁紙・スクリプトを入れる | `overlay/` 以下に、OS 内と同じパスで置く |
| 新規ユーザーのホームに配るファイル | `overlay/etc/skel/` |
| 任意の処理 (PPA 追加、設定変更など) | `hooks/` に `50-xxx.sh` のように番号付きで追加 |
| 起動メニュー | `config/grub.cfg` |

例: テキストエディタとゲームを追加する → `config/packages/extra.list` に
```
geany
supertuxkart
```
と書いて `make iso`。

## 次のステップのアイデア

- **インストーラー**: 今はライブ起動のみ。[Calamares](https://calamares.io/) を入れると HDD/SSD にインストールできるようになります
- **見た目**: 壁紙・テーマ・アイコンを `overlay/` に置いて `/etc/xdg/` や `/etc/skel/` の設定で既定にする
- **起動画面**: Plymouth のテーマを自作する (`/usr/share/plymouth/themes/`)
- **独自パッケージ**: 自作アプリを `.deb` にして独自 APT リポジトリから配布する

## ライセンスについて

中身のソフトウェアはそれぞれのライセンス (主に GPL など) に従います。
配布する場合、Ubuntu の商標 (名前・ロゴ) は使わないようにしてください (OS 名と起動画面は置き換え済みですが、デスクトップのロゴや壁紙などに Ubuntu/Xubuntu のものが残っている場合があります)。
