# General Devcontainer

Mac とほぼ同じ体験で開発できる汎用 Docker 開発環境。

## 特徴

- **git worktree 対応**: `worktree.useRelativePaths = true` (git >= 2.48) でコンテナ内でも worktree が問題なく動作
- **SSH 鍵共有**: ホストの `~/.ssh` から鍵ファイルをコピー（macOS 固有の config はスキップ）
- **HTTPS → SSH 自動変換**: `insteadOf` 設定で GitHub の HTTPS URL を SSH に変換（サブモジュール等も対応）
- **ホームディレクトリ永続化**: 名前付きボリュームでツール・設定を永続化（mise, claude, gh auth, zsh_history 等）
- **ソースコード共有**: `~/devcontainer-ghq` をバインドマウントし、Finder からもアクセス可能
- **Docker-outside-of-Docker**: ホストの Docker デーモンを共有

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
| `/var/run/docker.sock` | バインドマウント   | Docker-outside-of-Docker                 |
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

- コンテナ → インターネット: NAT 経由
- コンテナ → ホストの localhost: `host.docker.internal`

## 完全リセット

```bash
# ボリュームごと削除（ツール・設定・履歴すべてリセット）
docker compose down -v

# ソースコードはホストの ~/devcontainer-ghq に残る
```

## 注意事項

- コンテナ内からの `docker run -v $(pwd):/app` はパスがホスト基準になるため使えない
- `gh auth login` はコンテナ内で個別に実行が必要（ホストの認証は共有されない）
