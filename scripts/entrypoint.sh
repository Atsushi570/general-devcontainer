#!/bin/bash
set -e

SKEL_DIR="/etc/skel"
HOME_DIR="/home/devuser"

# =============================================================================
# 1. Home directory initialization (copy dotfiles from /etc/skel if missing)
# =============================================================================
init_dotfiles() {
  local marker="$HOME_DIR/.devcontainer-initialized"
  local fresh_install=false

  if [ ! -f "$marker" ]; then
    fresh_install=true
  fi

  # Oh My Zsh (if not present in volume)
  if [ ! -d "$HOME_DIR/.oh-my-zsh" ]; then
    echo "[entrypoint] Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    git clone https://github.com/zsh-users/zsh-completions \
      "${ZSH_CUSTOM:-$HOME_DIR/.oh-my-zsh/custom}/plugins/zsh-completions" 2>/dev/null || true
  fi

  # Copy dotfiles from /etc/skel/
  # Fresh volume: always copy (overwrite Oh My Zsh's default .zshrc and Dockerfile's copies)
  # Existing volume: only copy if file doesn't exist
  local files=(".zshrc" ".gitconfig" ".tmux.conf" ".config/mise/config.toml")
  for f in "${files[@]}"; do
    if [ "$fresh_install" = true ] || [ ! -f "$HOME_DIR/$f" ]; then
      if [ -f "$SKEL_DIR/$f" ]; then
        mkdir -p "$(dirname "$HOME_DIR/$f")"
        cp "$SKEL_DIR/$f" "$HOME_DIR/$f"
        echo "[entrypoint] Copied $f from /etc/skel/"
      fi
    fi
  done

  touch "$marker"

  # TPM (if not present in volume)
  if [ ! -d "$HOME_DIR/.tmux/plugins/tpm" ]; then
    echo "[entrypoint] Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm "$HOME_DIR/.tmux/plugins/tpm" 2>/dev/null || true
  fi

  # mise binary (if not present in volume)
  if [ ! -f "$HOME_DIR/.local/bin/mise" ]; then
    echo "[entrypoint] Installing mise..."
    curl -fsSL https://mise.run | sh
  fi

  # Claude Code (if not present in volume)
  if ! command -v claude &>/dev/null; then
    echo "[entrypoint] Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | sh
  fi
}

# =============================================================================
# 2. Docker socket GID detection
# =============================================================================
setup_docker() {
  if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    if [ "$DOCKER_GID" = "0" ]; then
      # Docker Desktop for Mac: socket is owned by root, just allow access via chmod
      sudo chmod 666 /var/run/docker.sock
      echo "[entrypoint] Docker socket ready (root-owned, chmod 666)"
    else
      if ! getent group docker &>/dev/null; then
        sudo groupadd -g "$DOCKER_GID" docker
      else
        CURRENT_GID=$(getent group docker | cut -d: -f3)
        if [ "$CURRENT_GID" != "$DOCKER_GID" ]; then
          sudo groupmod -g "$DOCKER_GID" docker
        fi
      fi
      if ! id -nG devuser | grep -qw docker; then
        sudo usermod -aG docker devuser
      fi
      echo "[entrypoint] Docker socket ready (GID: $DOCKER_GID)"
    fi
  fi
}

# =============================================================================
# 3. Fix home directory ownership
# =============================================================================
fix_ownership() {
  sudo chown -R devuser:devuser "$HOME_DIR" 2>/dev/null || true
}

# =============================================================================
# 4. SSH keys setup (copy keys from host mount, skip macOS-specific config)
# =============================================================================
setup_ssh() {
  if [ -d "$HOME_DIR/.host-ssh" ]; then
    mkdir -p "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    # Copy key files and known_hosts only (skip macOS config)
    for f in "$HOME_DIR/.host-ssh/"id_* "$HOME_DIR/.host-ssh/known_hosts"*; do
      [ -f "$f" ] || continue
      local basename
      basename=$(basename "$f")
      cp "$f" "$HOME_DIR/.ssh/$basename"
      chmod 600 "$HOME_DIR/.ssh/$basename"
    done
    # Make public keys readable
    chmod 644 "$HOME_DIR/.ssh/"*.pub 2>/dev/null || true
    echo "[entrypoint] SSH keys copied from host"
  else
    echo "[entrypoint] WARNING: No SSH keys found - mount ~/.ssh from host"
  fi
}

# =============================================================================
# 5. Git config (force set critical settings)
# =============================================================================
setup_git() {
  git config --global worktree.useRelativePaths true
  git config --global ghq.root ~/ghq
  echo "[entrypoint] Git configured (worktree.useRelativePaths=true, ghq.root=~/ghq)"

  # gwq config (match host: worktrees in ~/ghq alongside repos)
  gwq config set worktree.basedir ~/ghq 2>/dev/null || true
  gwq config set naming.template '{{.Host}}/{{.Owner}}/{{.Repository}}@{{.Branch}}' 2>/dev/null || true
  echo "[entrypoint] gwq configured (basedir=~/ghq)"
}

# =============================================================================
# 6. AWS config sync (host → container, initial only)
# =============================================================================
sync_aws() {
  if [ -d "$HOME_DIR/.host-aws" ] && [ ! -d "$HOME_DIR/.aws" ]; then
    cp -r "$HOME_DIR/.host-aws" "$HOME_DIR/.aws"
    echo "[entrypoint] AWS config synced from host"
  fi
}

# =============================================================================
# 7. GWS config sync (host → container, initial only)
# =============================================================================
sync_gws() {
  if [ -d "$HOME_DIR/.host-gws" ] && [ ! -d "$HOME_DIR/.config/gws" ]; then
    mkdir -p "$HOME_DIR/.config"
    cp -r "$HOME_DIR/.host-gws" "$HOME_DIR/.config/gws"
    echo "[entrypoint] GWS config synced from host"
  fi
}

# =============================================================================
# 7. mise install (install missing runtimes)
# =============================================================================
install_runtimes() {
  if command -v mise &>/dev/null; then
    echo "[entrypoint] Running mise install (this may take a while on first run)..."
    mise install --yes 2>&1 || echo "[entrypoint] WARNING: mise install had errors (non-fatal)"
  fi
}

# =============================================================================
# Main
# =============================================================================
echo "[entrypoint] Initializing devcontainer..."

init_dotfiles
setup_docker
fix_ownership
setup_ssh
setup_git
sync_aws
sync_gws
install_runtimes

echo "[entrypoint] Ready!"

exec "$@"
