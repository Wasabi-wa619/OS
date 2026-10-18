# WasabiOS

MacBook (2012年前後の Intel Mac) のために作っている自作 OS です。

```
電源 ON
 └─ GRUB (起動メニュー)
     └─ WasabiOS カーネル   … Linux 本家のソースを自分でビルド (起動ロゴはわさび)
         └─ wasabi-init      … 自作 (C 言語)。USB や SSD から OS を見つけて引き継ぐ。失敗したらレスキュー画面
             └─ systemd → GNOME デスクトップ、アプリ … Ubuntu 24.04 から借りる
```

- **自分で作っているところ**: カーネルのビルドと設定、最初に動くプログラム (init)、起動の仕組み (initramfs)、
  インストーラー、`wasabi` コマンド、見た目
- **Ubuntu から借りているところ**: デスクトップ (GNOME)、アプリ、apt / snap、ドライバーのファームウェアなど

カーネルの設定は Ubuntu と同じものを土台にしているので、**Ubuntu のアプリ・snap・PPA・Docker などはそのまま動きます**。
OS の内部的な ID (`ID=ubuntu`) も Ubuntu のままにしてあるので、「Ubuntu 用」のインストーラーも使えます。

## 使い方は3通り

| | A. ライブ USB → インストール | B. いまの Ubuntu に入れる | C. シード版 |
|---|---|---|---|
| 中身 | フル版 (自作カーネル + 自作 init + Ubuntu のアプリ) | 見た目と `wasabi` コマンドだけ | 自作 init だけで動く 27MB の小さい OS |
| 使い方 | USB で試す → `WasabiOS をインストール` で SSD へ | `make install` | 仮想マシンや USB で遊ぶ |
| 保存 | インストールすれば保存される (ライブでも WASABI-DATA パーティションがあれば保存) | 今まで通り | されない |
| 詳しく | 下の「A」 | 下の「B」 | [`scratch/`](scratch/README.md) |

## WasabiOS の独自部分

| パッケージ | 中身 |
|---|---|
| `wasabios-base` | OS 名とロゴ (設定 → システム → 情報 に出る)、`wasabi` コマンド、ターミナルの挨拶 |
| `wasabios-desktop` | 壁紙、緑のテーマ (Yaru-sage ダーク)、起動画面のロゴ |
| `wasabios-mac` | MacBook 向け: ファン制御 (mbpfan)、温度センサー |
| `wasabios-boot` | 自作 init (wasabi-init) と、それを詰めた起動用の initramfs を作る `wasabi-mkinitramfs`。Ubuntu の initramfs-tools の代わり |
| `wasabios-installer` | SSD へのインストーラー `wasabi-install` (ライブ USB だけに入っている) |

### `wasabi` コマンド

```
wasabi info      このパソコンの情報を表示
wasabi update    OS とアプリをまとめて最新にする (apt / snap / flatpak)
wasabi clean     不要なファイルを掃除して空き容量を増やす
wasabi doctor    よくある問題をチェックする (MacBook の Wi-Fi・ファン・バッテリー)
wasabi theme     壁紙と色を WasabiOS の標準に戻す
```

### 前の状態に戻す (WasabiOS Restore)

Chrome OS のように、システムが壊れても前の状態に戻せます (SSD にインストールした WasabiOS)。

- アップデートやアプリのインストールの **直前に自動でシステムの状態を保存** (新しい 5 個まで)
- 戻しても **自分のファイル (/home) は消えない** (システムと自分のファイルは別の場所にある)
- 戻す作業は、OS が起動する前に **自作の wasabi-init が行う**ので、OS が起動しなくなっても戻せる

```
wasabi snapshot              保存してある状態の一覧
wasabi snapshot save 名前    今の状態を保存
wasabi rollback 番号         次の再起動でその状態に戻す
wasabi powerwash             インストール直後の状態に戻す (自分のファイルは残る)
wasabi snapshot clean        戻す前の古いシステムを消して容量を空ける
```

**起動しなくなったとき**: 起動メニュー (GRUB) で **「WasabiOS を前の状態に戻す (Restore)」** を選ぶと、
保存してある状態の一覧が出ます。番号を入れて `yes` で戻ります。

しくみ: ディスクは btrfs で、システム (`@`)・自分のファイル (`@home`)・保存した状態 (`@snapshots`) に分かれています。
戻すときは `@` を保存しておいた状態と入れ替えるだけなので一瞬です (`scratch/init/restore.c`)。

### Ubuntu との互換性について

OS の内部的な ID (`/etc/os-release` の `ID=ubuntu` や `lsb_release -i`) は Ubuntu のまま残し、
**表示名だけ**を WasabiOS にしています。
ID まで変えると、Docker や VS Code、Steam などのインストーラーや PPA が「対応していない OS」と判断してしまうためです。
Ubuntu のアップデートで os-release が更新されても、自動で WasabiOS の名前が付け直されます。

---

## A. ライブ USB を作って、試して、インストールする

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
  初回は WasabiOS カーネルのビルドに 1〜3 時間かかります (2回目からは作ったものを使う)。

### 仮想マシンで試す (USB なしで、いまの Ubuntu の中で)

MacBook の Ubuntu の中に仮想のパソコンを作って、WasabiOS を起動できます。
インストールも仮想の SSD に対して行うので、本物のディスクには何も起きません。

```bash
make deps                                  # QEMU などを入れる (初回のみ)
make vm ISO=~/ダウンロード/wasabios-0.1-amd64.iso   # ISO から起動 (ライブ USB の代わり)
```

- 開いたウィンドウの中で WasabiOS が動きます。Dock の「WasabiOS をインストール」で仮想 SSD にインストールも試せます
  (インストール先は `/dev/vda`)
- インストールしたあとは `make vm-disk` で、仮想 SSD から起動 (USB を抜いた状態)
- 最初からやり直す: `make vm-reset`
- 自分でビルドした ISO なら `ISO=...` は省略できます
- マウスがウィンドウから出られなくなったら **Ctrl + Alt + G**
- 重いときはメモリを増やす: `make vm MEM=4096` (MacBook のメモリの半分くらいまで)

### Chromebook で USB に書き込む

1. Chromebook に Chrome ウェブストアの **Chromebook リカバリ ユーティリティ** を入れる
2. ダウンロードした ISO の名前を `wasabios-0.1-amd64.iso` → `wasabios-0.1-amd64.bin` に変える
3. ユーティリティの右上の歯車 → **ローカル イメージを使用** → その .bin を選んで USB に書き込む
   (USB の中身は消えます)

MacBook の Ubuntu で書き込む場合は「ディスク」アプリ → USB を選択 → 右上のメニュー → **ディスクイメージを復元** でも OK です。

### MacBook で USB から起動する

USB を挿して電源を入れ、すぐに **option (⌥) キー** を押し続けます。
起動ディスクの選択画面が出たら **EFI Boot** を選びます。

起動メニュー:
- **WasabiOS を起動**: ふつうに起動 (ライブ)。変更はメモリ上にだけ残る
- **セーフグラフィックス**: 画面が真っ暗になるとき
- **メモリに全部読み込む**: 起動後に USB を抜ける (メモリ 4GB 以上)
- **レスキュー**: 自作 init のシェルだけで起動 (トラブル調査用)

### SSD にインストールする

ライブ USB で起動したら、左の Dock の **WasabiOS をインストール** をクリックします
(ターミナルで `sudo wasabi-install` でも同じ)。

- **ディスク全体を使う**: 選んだディスクを全部消して WasabiOS だけにする
- **パーティションを選ぶ**: 元の Ubuntu などを残す。先に GParted (ライブ USB に入っています) で
  空きパーティションを作っておく。起動メニューに元の OS も出ます

### ライブ USB のまま保存したいとき

どこかのディスク (別の USB でも OK) に、ラベルが **WASABI-DATA** の ext4 パーティションを作っておくと、
ライブ起動のときの変更 (ファイル・設定・入れたアプリ) がそこに保存されます。

## B. いまの Ubuntu に入れる (見た目と wasabi コマンドだけ)

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

パッケージの版数は `OS_VERSION` + ビルド日時 (例 `0.1+202610161620`) になるので、作り直すたびに apt が新しいものとして入れます。

## ディレクトリ構成

```
config/      OS 名・ISO の設定、ISO に入れるパッケージ一覧
packages/    WasabiOS 独自パッケージの中身 (.deb の元)
artwork/     ロゴ・壁紙の元データ (SVG)
scripts/     build-debs.sh (.deb を作る) / install-on-ubuntu.sh / build.sh (ISO を作る)
scratch/     自作部分の中心: kernel/ (カーネル設定・ロゴ・ビルド)、init/ (wasabi-init のソース)、シード版
hooks/       ISO ビルド時に chroot 内で番号順に実行されるスクリプト
overlay/     ISO にそのまま上書きコピーされるファイル
```

ISO のビルドの流れ: WasabiOS カーネルを .deb にビルド (`scratch/kernel/build-kernel.sh`)
→ `debootstrap` で Ubuntu の最小システムを作る → `hooks/` でカーネルとパッケージ (WasabiOS の .deb を含む) を入れる
→ `squashfs` に圧縮 → GRUB で BIOS / UEFI 両対応の ISO にする。
起動すると自作の `wasabi-init` が ISO の中の `wasabios/root.squashfs` を見つけ、書き込み用の層を重ねて systemd に引き継ぎます。

## 注意: カーネルの更新

アプリや GNOME などは `wasabi update` (= apt) で Ubuntu から更新が届きます。
**カーネルだけは WasabiOS 自前なので、セキュリティ修正を自分で取り込む必要があります。**
新しいバージョンが出たら `scratch/versions.conf` を書き換えて作り直してください (`scratch/README.md`)。

## 次のステップのアイデア

- **GUI のインストーラー**: いまはターミナルで質問に答える形
- **独自 APT リポジトリ**: GitHub Pages で配布して、`wasabi update` で WasabiOS 自体も更新されるようにする
- **独自アプリ**: 設定アプリやウェルカム画面を作って `packages/` に足す

## ライセンスについて

中身のソフトウェアはそれぞれのライセンス (主に GPL など) に従います。
配布する場合は Ubuntu の商標 (名前・ロゴ) を自分の OS の名前として使わないでください
(WasabiOS は名前・ロゴ・壁紙・起動画面を置き換え済みです)。
