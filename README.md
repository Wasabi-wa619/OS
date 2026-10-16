# WasabiOS

Ubuntu をベースにした自作 OS です。
**Ubuntu のアプリ・機能 (apt / snap / PPA / ソフトウェアセンターなど) はそのまま使えて**、
その上に WasabiOS 独自の名前・見た目・コマンドを足しています。

Ubuntu 自体も Debian に独自パッケージを足して作られていて、Kubuntu や Pop!_OS なども同じ考え方です。
WasabiOS の独自部分はすべて `packages/` の中の **.deb パッケージ** になっているので、
次の2通りで使えます。

| | A. いまの Ubuntu に入れる | B. ISO を作って USB から起動 |
|---|---|---|
| こんなとき | **MacBook の Ubuntu をそのまま WasabiOS にする** | 他の PC で試す・配る |
| 再インストール | 不要 (データもアプリもそのまま) | ライブ起動のみ (インストーラーは今後) |
| USB メモリ | 不要 | 必要 |
| 元に戻す | `make uninstall` で Ubuntu に戻る | USB を抜くだけ |

## WasabiOS の独自部分

| パッケージ | 中身 |
|---|---|
| `wasabios-base` | OS 名とロゴ (設定 → システム → 情報 に出る)、`wasabi` コマンド、ターミナルの挨拶 |
| `wasabios-desktop` | 壁紙、緑のテーマ (Yaru-sage ダーク)、起動画面のロゴ |
| `wasabios-mac` | MacBook 向け: ファン制御 (mbpfan)、温度センサー |

### `wasabi` コマンド

```
wasabi info      このパソコンの情報を表示
wasabi update    OS とアプリをまとめて最新にする (apt / snap / flatpak)
wasabi clean     不要なファイルを掃除して空き容量を増やす
wasabi doctor    よくある問題をチェックする (MacBook の Wi-Fi・ファン・バッテリー)
wasabi theme     壁紙と色を WasabiOS の標準に戻す
```

### Ubuntu との互換性について

OS の内部的な ID (`/etc/os-release` の `ID=ubuntu` や `lsb_release -i`) は Ubuntu のまま残し、
**表示名だけ**を WasabiOS にしています。
ID まで変えると、Docker や VS Code、Steam などのインストーラーや PPA が「対応していない OS」と判断してしまうためです。
Ubuntu のアップデートで os-release が更新されても、自動で WasabiOS の名前が付け直されます。

---

## A. MacBook (いまの Ubuntu) に入れる

MacBook のターミナルで:

```bash
sudo apt install -y git make
git clone https://github.com/wasabi-wa619/os.git
cd os
make install
```

終わったら再起動すると、起動画面・壁紙・テーマが WasabiOS になります。
Mac であることは自動で判定して `wasabios-mac` も入ります。

- 壁紙を前に自分で変えていた場合はそちらが優先されます → `wasabi theme` で WasabiOS の見た目に
- 改造したら: `git pull` してから (または自分で書き換えてから) もう一度 `make install`
- 元に戻す: `make uninstall` (Ubuntu の名前・壁紙・起動画面に戻ります)

> リポジトリが非公開の場合、`git clone` で GitHub のログインを求められます。
> パスワードの代わりに [Personal access token](https://github.com/settings/tokens) を使うか、
> `sudo apt install gh && gh auth login` でログインしてから clone してください。

## B. ISO (ライブ USB) を作る

### ビルド

- **GitHub で作る (おすすめ)**: リポジトリの **Actions** → **Build** → **Run workflow**。
  30〜60分で Artifacts から ISO をダウンロードできます。
- **MacBook の Ubuntu で作る**: 20GB ほどの空きが必要です。
  ```bash
  make deps          # ビルドツールを入れる (初回のみ)
  make iso           # → out/wasabios-0.1-amd64.iso
  make run           # QEMU で試す
  ```
  `make iso DESKTOP=xfce` で軽いデスクトップ、`MAC_SUPPORT=no` で Mac 用ドライバーなし。

### Chromebook で USB に書き込む

1. Chromebook に Chrome ウェブストアの **Chromebook リカバリ ユーティリティ** を入れる
2. ダウンロードした ISO の名前を `wasabios-0.1-amd64.iso` → `wasabios-0.1-amd64.bin` に変える
3. ユーティリティの右上の歯車 → **ローカル イメージを使用** → その .bin を選んで USB に書き込む
   (USB の中身は消えます)

MacBook の Ubuntu で書き込む場合は「ディスク」アプリ → USB を選択 → 右上のメニュー → **ディスクイメージを復元** でも OK です。

### MacBook で USB から起動する

USB を挿して電源を入れ、すぐに **option (⌥) キー** を押し続けます。
起動ディスクの選択画面が出たら **EFI Boot** を選びます。

---

## カスタマイズ

| やりたいこと | 編集する場所 |
|---|---|
| OS の名前・バージョン | `config/os.conf` |
| `wasabi` に新しいコマンドを足す | `packages/wasabios-base/usr/bin/wasabi` に `cmd_xxx` 関数を足す |
| 壁紙・ロゴ・起動画面のロゴ | `artwork/` の SVG を編集 (ビルド時にパッケージに入る) |
| テーマの色 | `packages/wasabios-desktop/usr/share/glib-2.0/schemas/90_wasabios.gschema.override` |
| 独自ファイルを OS に入れる | `packages/<パッケージ>/` の下に OS 内と同じパスで置く |
| ISO に入れるアプリ | `config/packages/extra.list` |
| ISO だけの設定 | `hooks/`、`overlay/`、`config/grub.cfg` |

パッケージを配り直すときは `config/os.conf` の `OS_VERSION` を上げると、apt が「新しいバージョン」として扱います。

## ディレクトリ構成

```
config/      OS 名・ISO の設定、ISO に入れるパッケージ一覧
packages/    WasabiOS 独自パッケージの中身 (.deb の元)
artwork/     ロゴ・壁紙の元データ (SVG)
scripts/     build-debs.sh (.deb を作る) / install-on-ubuntu.sh / build.sh (ISO を作る)
hooks/       ISO ビルド時に chroot 内で番号順に実行されるスクリプト
overlay/     ISO にそのまま上書きコピーされるファイル
```

ISO のビルドの流れ: `debootstrap` で Ubuntu の最小システムを作る → `hooks/` でパッケージ (WasabiOS の .deb を含む) を入れる
→ `squashfs` に圧縮 → GRUB で BIOS / UEFI 両対応の ISO にする。ライブ起動には Ubuntu と同じ `casper` を使っています。

## 次のステップのアイデア

- **インストーラー**: ISO に Calamares を入れて SSD にインストールできるようにする
- **独自 APT リポジトリ**: GitHub Pages で配布して、`wasabi update` で WasabiOS 自体も更新されるようにする
- **独自アプリ**: 設定アプリやウェルカム画面を作って `packages/` に足す

## ライセンスについて

中身のソフトウェアはそれぞれのライセンス (主に GPL など) に従います。
配布する場合は Ubuntu の商標 (名前・ロゴ) を自分の OS の名前として使わないでください
(WasabiOS は名前・ロゴ・壁紙・起動画面を置き換え済みです)。
