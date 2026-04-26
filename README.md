# General Devcontainer

Mac とほぼ同じ体験で開発できる汎用 Docker 開発環境。

## 特徴

- **git worktree 対応**: `worktree.useRelativePaths = true` (git >= 2.48) でコンテナ内でも worktree が問題なく動作
- **SSH 鍵共有**: ホストの `~/.ssh` から鍵ファイルをコピー（macOS 固有の config はスキップ）
- **HTTPS → SSH 自動変換**: `insteadOf` 設定で GitHub の HTTPS URL を SSH に変換（サブモジュール等も対応）
- **ホームディレクトリ永続化**: 名前付きボリュームでツール・設定を永続化（mise, claude, gh auth, zsh_history 等）
- **ソースコード共有**: `~/devcontainer-ghq` をバインドマウントし、Finder からもアクセス可能
- **Docker-in-Docker（DinD）**: 専用のサイドカーコンテナで独立した Docker デーモンを動かし、`docker run -v $(pwd):/...` などホストパス依存のないクリーンな挙動を実現
- **ホスト Docker へのフォールバック**: ホストの Docker デーモンも `DOCKER_HOST=unix:///var/run/host-docker.sock` で利用可能
- **Host networking**: `network_mode: host` でコンテナ内のポートをそのまま Mac から `localhost` でアクセス可能（ポート公開設定不要）

## 含まれるツール

| カテゴリ       | ツール                                       |
| -------------- | -------------------------------------------- |
| Git            | git (>= 2.48, PPA)                           |
| シェル         | zsh, Oh My Zsh (af-magic), zsh-completions   |
| 開発ツール     | tmux, fzf, ripgrep, jq, build-essential      |
| GitHub         | gh (GitHub CLI)                              |
| リポジトリ管理 | ghq                                          |
| タスクランナー | go-task                                      |
| Docker         | docker-ce-cli, docker-compose-plugin         |
| ランタイム管理 | mise (Node.js LTS, Python, Go, Java zulu-25) |
| クラウド       | AWS CLI v2                                   |
| IaC            | Terraform                                    |
| AI             | Claude Code                                  |

## セットアップ

```bash
# 初回
mkdir -p ~/devcontainer-ghq
docker compose up -d --build
# 初回は mise install が走るため少し時間がかかる

# コンテナに入る
docker exec -it general-dev zsh
```

## 日常の使い方

```bash
# コンテナ起動
docker compose up -d

# コンテナに入る
docker exec -it general-dev zsh

# コンテナ内での操作
ghq get git@github.com:org/repo.git    # リポジトリクローン
dev                                     # fzf でリポジトリ選択
claude                                  # Claude Code 起動（初回は claude login）
gh auth login                           # GitHub CLI 認証（初回のみ）
git worktree add ../feature branch      # worktree も問題なし
git push                                # SSH 鍵で認証
aws sso login                           # AWS SSO（プロファイルはホストから同期済み）
docker ps                               # ホストの Docker を操作
```

## ボリューム構成

| マウント先             | 方式               | 内容                                     |
| ---------------------- | ------------------ | ---------------------------------------- |
| `/home/devuser`        | 名前付きボリューム | ツール・設定の永続化（mise, claude 等）   |
| `/home/devuser/ghq`    | バインドマウント   | ソースコード（ホストの Finder からアクセス可能） |
| `/var/run/host-docker.sock` | バインドマウント   | ホストの Docker ソケット（フォールバック用） |
| `/home/devuser/.host-ssh` | バインドマウント (ro) | ホストの SSH 鍵（entrypoint で鍵のみコピー） |
| `/home/devuser/.host-aws` | バインドマウント (ro) | ホストの AWS プロファイル（初回コピー）  |

## ドットファイル更新

Dockerfile を更新してイメージを再ビルドした場合、`/etc/skel/` には新しいファイルが入るが、ボリューム上の既存ファイルは上書きされない（ユーザーのカスタマイズを保持）。

```bash
# イメージ再ビルド
docker compose up -d --build

# 強制的にドットファイルを更新したい場合
docker exec general-dev cp /etc/skel/.zshrc ~/
docker exec general-dev cp /etc/skel/.gitconfig ~/
docker exec general-dev cp /etc/skel/.tmux.conf ~/
docker exec general-dev cp /etc/skel/.config/mise/config.toml ~/.config/mise/config.toml
```

## ネットワーク

`network_mode: host` を使用しており、コンテナはホスト（Docker Desktop の Linux VM）と同じネットワーク名前空間を共有する。

- コンテナ内で起動したサーバ（Streamlit, Vite, FastAPI 等）はポート公開設定なしで Mac から `http://localhost:<port>` でアクセス可能
- `--server.address=0.0.0.0` のような bind 指定も不要（デフォルトの localhost で OK）
- コンテナ → ホストの localhost も `localhost` でアクセス可能

### 前提条件（Mac の場合）

Docker Desktop for Mac で host networking を使うには以下が必要:

1. Docker Desktop 4.29+
2. Docker アカウントへサインイン（無料アカウントで可）
3. Settings → Resources → Network → **Enable host networking** を ON

## Docker（DinD + ホストフォールバック）

このコンテナは **DinD（Docker-in-Docker）** 構成。`docker compose up -d` で `general-dev`（メイン）と `general-dev-dind`（サイドカー）の 2 コンテナが起動し、メインの `docker` CLI は環境変数 `DOCKER_HOST=tcp://127.0.0.1:2375` 経由で DinD サイドカーに接続する。

### なぜ DinD か

DooD（ホストソケット直接マウント）だと、コンテナ内で `docker run -v $(pwd):/app` のように相対パスをマウントしようとした際、`$(pwd)` がコンテナ内パス（例: `/home/devuser/ghq/...`）として展開され、ホスト側のデーモンには存在しないパスとして渡って失敗する。DinD では Docker デーモンがコンテナ内で動くため、コンテナ内のパスがそのまま解釈される。

### ソースコード共有

DinD サイドカーにも `~/devcontainer-ghq` を `/home/devuser/ghq` に同じパスでマウントしているため、メインから `docker run -v /home/devuser/ghq/foo:/src ...` としたとき DinD 側でも同じファイルが見える。

### ホストの Docker を使いたい場合

ホストで動いているコンテナを操作したい、ホストで pull 済みのイメージを使いたい等のケースは `DOCKER_HOST` を切り替える:

```bash
# ホストの Docker
DOCKER_HOST=unix:///var/run/host-docker.sock docker ps

# 頻繁に使うならエイリアス
alias dockerh='DOCKER_HOST=unix:///var/run/host-docker.sock docker'
```

### 注意点

- DinD のイメージ・ビルドキャッシュはホストの Docker と分離されている（`dind-data` という名前付きボリュームで永続化）
- ホストで pull 済みのイメージも DinD では再 pull が必要

## 完全リセット

```bash
# ボリュームごと削除（ツール・設定・履歴すべてリセット）
docker compose down -v

# ソースコードはホストの ~/devcontainer-ghq に残る
```

## 注意事項

- `gh auth login` はコンテナ内で個別に実行が必要（ホストの認証は共有されない）
- DinD と Mac のホスト Docker でイメージ／ビルドキャッシュは独立しているので、必要に応じて両方で pull／build する
