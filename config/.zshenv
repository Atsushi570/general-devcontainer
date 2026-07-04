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

# Same reason as PATH above: docker-compose.yml sets DOCKER_HOST as a container
# ENV, but SSH login sessions (Zed remote via sshd on port 2223) do NOT inherit
# it, so `docker` would fall back to the non-existent unix:///var/run/docker.sock.
# Point it at the DinD sidecar here so Zed terminals work too.
export DOCKER_HOST=tcp://127.0.0.1:2375
