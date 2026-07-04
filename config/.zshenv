# Read by zsh for ALL invocations (login / interactive / non-interactive),
# unlike the Dockerfile `ENV PATH` which SSH sessions (Zed remote via sshd)
# do NOT inherit. Ensures mise (~/.local/bin) and its shims are on PATH so
# `.zshrc`'s `mise activate` and non-interactive `ssh host <cmd>` both work.
if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi
if [ -d "$HOME/.local/share/mise/shims" ]; then
  export PATH="$HOME/.local/share/mise/shims:$PATH"
fi
