# host-helper: コンテナから Mac の決まったコマンドだけを実行する

Docker Desktop for Mac では、SD カードや USB をデバイスとしてコンテナに渡せない。そこでコンテナから ssh で Mac に入り、許可リストにあるコマンドだけを実行できるようにする。最初の用途は、センサのイメージを `dd` で SD カードに書き込むこと。

初回は「セットアップ」を上から順に実施する。2 回目以降は「使い方」と「サブコマンドを足す」だけ読めばよい。

## 何ができて、何ができないか

コンテナにある専用鍵 `~/.ssh/keys/mac_host` で Mac にログインすると、何を実行しようとしても `/usr/local/bin/host-helper` しか起動しない。`authorized_keys` の強制コマンドと `restrict` によるもので、シェル・ポート転送・pty も取れない。鍵が漏れても、被害は host-helper のサブコマンドを実行されることまでで止まる。

root 権限は、sudoers に 1 行ずつ書いたサブコマンド（現在は `sd-write` だけ）にしか渡さない。`dd` や `diskutil` そのものは許可していない。

コンテナにはホストの `~/.ssh/id_rsa` もコピーされている（entrypoint の rsync による）。**Mac の `authorized_keys` に `id_rsa.pub` を制限なしで入れてはいけない**。入れると、コンテナから Mac のシェルに無制限で入れてしまう。

## セットアップ（Mac で 1 回）

1. **リモートログインを ON にする。** システム設定 → 一般 → 共有 → リモートログイン。install.sh が Mac のホスト鍵を読むので、先に ON にしておく。
2. **install.sh を実行する。** Mac のターミナルで、普段のユーザーのまま実行する（途中で sudo のパスワードを聞かれる）。

   ```bash
   ~/devcontainer-ghq/github.com/Atsushi570/general-devcontainer/host/install.sh
   ```

   次のものが入る。何度実行しても同じ状態になる。

   | 作られるもの | 中身 |
   |---|---|
   | `/usr/local/bin/host-helper`、`/usr/local/libexec/host-helper/` | 本体。root 所有・755 なので、ユーザー権限では書き換えられない |
   | `/etc/sudoers.d/host-helper` | `ROOT_COMMANDS` に挙げたサブコマンドだけを NOPASSWD にする。`visudo -c` で検証してから置く |
   | `~/.ssh/keys/mac_host` | 専用鍵。`keys/` はコンテナにライブマウントされているので、すぐコンテナから見える |
   | `~/.ssh/authorized_keys` | 上の鍵を `command="/usr/local/bin/host-helper",restrict` 付きで 1 行追加する |
   | `~/.ssh/keys/devcontainer.conf`、`known_hosts_mac_host` | コンテナ用の ssh 設定と、Mac のホスト鍵のピン留め |
   | `~/.ssh/config` の先頭 | `Include keys/devcontainer.conf` を 1 行追加する |

3. **コンテナの `~/.ssh/config` にも Include を入れる。** コンテナの `~/.ssh/config` はコンテナ起動時にしか同期されないため、動いているコンテナにはまだ届いていない。再起動する（`docker compose restart dev`）か、コンテナ内で次を 1 回実行する。

   ```bash
   grep -qxF 'Include keys/devcontainer.conf' ~/.ssh/config || sed -i '1i Include keys/devcontainer.conf' ~/.ssh/config
   ```

4. **接続を確かめる。** コンテナから `ssh mac-host ping` を実行し、`pong from <Mac名> as <ユーザー名>` が返れば完了。

接続先の `192.168.65.254` は、Docker Desktop のホストゲートウェイのアドレス。`network_mode: host` では `host.docker.internal` が名前解決できないので、IP を直接書いている。ホスト鍵は install.sh が Mac 自身の鍵をピン留めしているので、別の sshd に取り違えて接続することはない。

## 使い方

```bash
ssh mac-host help
ssh mac-host sd list
# DISK     BYTES          SIZE     PROTOCOL         MEDIA
# disk4    31914983424    31.9GB   Secure Digital   SD Card Reader

ssh mac-host sd write ~/ghq/path/to/pir-v1.2.img.xz disk4 31914983424
```

- `sd list` には、取り外し可能な物理ディスクで、128 GiB 以下、かつ起動ディスクでないものだけが出る。
- `sd write` の 3 つ目の引数には、`sd list` の BYTES 列をそのまま渡す。カードを挿し直すとディスク番号が変わることがあるため、容量が一致しないと書き込まない。
- イメージのパスは、コンテナのパス（`~/ghq/...`）でも Mac のパス（`~/devcontainer-ghq/...`）でもよい。それ以外の場所にあるファイルは受け付けない。
- `.xz` / `.gz` / `.zst` は Mac 側で展開しながら書き込む。`xz` と `zstd` は Homebrew で入れておく。展開は一般ユーザー権限で行い、root で動くのは `dd` の部分だけ。
- 書き終わるとディスクを eject する。数 GB のイメージだと数分かかる。

### センサの identity をカードに書く（`sd identity`）

```bash
ssh mac-host sd identity ~/ghq/path/to/cards/01 disk4 31914983424
```

master イメージを書いた（またはデュプリケーターで複製した）カードの identity 投入口へ、機体ごとの identity を書き込む。投入口はラベルで見分ける。

| ラベル | センサ | 中身 |
|---|---|---|
| `MW_BOOT` | PIR（Armbian） | identity 専用の空の FAT。identity 以外のファイルがあれば中断する |
| `bootfs` | 赤外線アレイ（Raspberry Pi OS） | Pi の `/boot/firmware` そのもの。OS のファイルがあるので、`config.txt`・`cmdline.txt`・`mw-master-image` が揃っていることを確かめる（mw-kit と同じ条件）。identity 以外のファイルには触らない |
master は 1 枚だけ `sd write` で作り、残りを複製してから 1 枚ずつこれを流す、という使い方を想定している。

- `<dir>` には `identity.json`・`thingCert.crt`・`privKey.key`（必須）と `authorized_keys`（任意）だけが入っていること。それ以外のファイルがあると中断する。`mw-kit issue --card <dir>/MW_BOOT` の出力先をそのまま渡せばよい。
- ディスクの確認は `sd write` と同じ（`sd list` に出るディスクで、容量が一致すること）。そのうえで、ラベルが `MW_BOOT` か `bootfs` の FAT パーティションがちょうど 1 つあることを確かめる。
- `etc/`・`greengrass/` があれば中断する（rootfs の取り違え）。前の identity が残っていれば置き換える。
- `cp -X` で書き、macOS が作る `._*`・`.Spotlight-V100`・`.fseventsd` などは消す。
- 書いたあと一度アンマウントしてから再マウントし、元のファイルと `cmp` で照合する。ページキャッシュではなくカードから読み戻すため。
- 最後に thingName を表示して eject する。
- root は要らない（`diskutil mount` は取り外し可能な FAT ボリュームを一般ユーザーでマウントできる）。sudoers は変わらない。
- `sd write` は書き終わると eject するので、`sd identity` の前にカードを挿し直し、`sd list` でディスク番号を確かめ直す。

## サブコマンドを足す

1. `host/libexec/<name>` にスクリプトを置く。
2. `host/host-helper` の `case "$cmd"` に、呼び出しを 1 つ足す。引数の検証はここ（一般ユーザー権限の側）で済ませる。
3. root が必要なら、`install.sh` の `ROOT_COMMANDS` に `<name>` を足す。root で動くスクリプトには、検証済みの最小限の引数だけを渡す。
4. Mac で `install.sh` を再実行する。リポジトリから消したサブコマンドは、`/usr/local/libexec/host-helper/` からも消える。

ssh 越しの引数は、英数字と `._/@:=+,-` とスペースしか通さない。スペースで単純に分割するので、スペースを含むパスは扱えない。

## 未検証の点

MacBook Pro（内蔵 SDXC リーダー）で確認できているのは、接続、強制コマンドによる制限（任意コマンドとポート転送の拒否）、`sd list`、`sd write`（PIR 6.7GB・赤外線アレイ 15GB、約 50MB/s）、`sd identity`（`MW_BOOT` 14 枚・`bootfs` 7 枚）まで。USB 接続のカードリーダーでの検出はまだ試していない。

`sd write` が `dd: /dev/rdiskN: Operation not permitted` で止まるときは、Mac のフルディスクアクセスが足りない。システム設定 → プライバシーとセキュリティ → フルディスクアクセスで `sshd-keygen-wrapper` を ON にする。root で動いていても、ssh 経由のプロセスはこれが無いと raw デバイスに書けない。
