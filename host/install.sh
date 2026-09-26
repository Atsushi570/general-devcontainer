#!/bin/bash
# Install host-helper on the Mac so the devcontainer can run a fixed set of
# host commands over ssh. Idempotent: re-run after adding or changing a
# subcommand. Run as your normal user on the Mac (uses sudo where needed).
set -euo pipefail

# Subcommands in libexec/ that may run as root. Each one gets its own sudoers
# line; everything else in libexec/ runs as the normal user.
ROOT_COMMANDS="sd-write"

# Docker Desktop's host gateway as seen from the container (host.docker.internal
# does not resolve under network_mode: host).
HOST_ADDR=192.168.65.254

PREFIX=/usr/local
LIBEXEC=$PREFIX/libexec/host-helper
KEY=$HOME/.ssh/keys/mac_host
KEY_TAG=devcontainer-host-helper

die() { echo "install.sh: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[ "$(uname -s)" = Darwin ] || die "run this on the Mac host, not in the container"
[ "$(id -u)" != 0 ] || die "run as your normal user (sudo is used where needed)"
here=$(cd "$(dirname "$0")" && pwd)
user=$(id -un)

log "installing scripts to $PREFIX (root-owned)"
sudo install -d -o root -g wheel -m 755 "$PREFIX/bin" "$LIBEXEC" "$LIBEXEC/lib"
sudo install -o root -g wheel -m 755 "$here/host-helper" "$PREFIX/bin/host-helper"
for f in "$here"/libexec/*; do
  sudo install -o root -g wheel -m 755 "$f" "$LIBEXEC/$(basename "$f")"
done
for f in "$here"/lib/*; do
  sudo install -o root -g wheel -m 644 "$f" "$LIBEXEC/lib/$(basename "$f")"
done
# Drop subcommands that were removed from the repo.
for f in "$LIBEXEC"/*; do
  [ -f "$f" ] && [ ! -e "$here/libexec/$(basename "$f")" ] && sudo rm -f "$f" && log "removed stale $f"
done

log "writing /etc/sudoers.d/host-helper"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  echo "# Managed by general-devcontainer/host/install.sh"
  for c in $ROOT_COMMANDS; do
    [ -f "$here/libexec/$c" ] || die "ROOT_COMMANDS lists missing libexec/$c"
    echo "$user ALL=(root) NOPASSWD: $LIBEXEC/$c"
  done
} >"$tmp"
sudo visudo -cf "$tmp" >/dev/null || die "generated sudoers failed validation"
sudo install -o root -g wheel -m 440 "$tmp" /etc/sudoers.d/host-helper

log "ssh key $KEY"
mkdir -p "$HOME/.ssh/keys"
chmod 700 "$HOME/.ssh" "$HOME/.ssh/keys"
[ -f "$KEY" ] || ssh-keygen -q -t ed25519 -N '' -C "$KEY_TAG" -f "$KEY"

log "authorizing the key (forced command: host-helper)"
ak=$HOME/.ssh/authorized_keys
touch "$ak"
chmod 600 "$ak"
{
  grep -v " $KEY_TAG\$" "$ak" || true
  echo "command=\"$PREFIX/bin/host-helper\",restrict $(cat "$KEY.pub")"
} >"$tmp"
cat "$tmp" >"$ak"

log "pinning this Mac's host key for the container"
hostkey=/etc/ssh/ssh_host_ed25519_key.pub
[ -r "$hostkey" ] || die "$hostkey not found (is Remote Login enabled?)"
echo "mac-host $(cut -d' ' -f1,2 "$hostkey")" >"$HOME/.ssh/keys/known_hosts_mac_host"

log "writing ~/.ssh/keys/devcontainer.conf"
cat >"$HOME/.ssh/keys/devcontainer.conf" <<EOF
# Managed by general-devcontainer/host/install.sh
# Used from inside the devcontainer; unused (and harmless) on the Mac itself.
Host mac-host
  HostName $HOST_ADDR
  User $user
  IdentityFile ~/.ssh/keys/mac_host
  IdentitiesOnly yes
  HostKeyAlias mac-host
  UserKnownHostsFile ~/.ssh/keys/known_hosts_mac_host
  StrictHostKeyChecking yes
EOF

cfg=$HOME/.ssh/config
line='Include keys/devcontainer.conf'
touch "$cfg"
if ! grep -qxF "$line" "$cfg"; then
  log "adding '$line' to the top of ~/.ssh/config"
  { echo "$line"; echo; cat "$cfg"; } >"$tmp"
  cat "$tmp" >"$cfg"
fi

if nc -z -G 2 localhost 22 >/dev/null 2>&1; then
  log "done. From the container: ssh mac-host ping"
else
  log "done, but nothing is listening on port 22."
  echo "    Turn on System Settings > General > Sharing > Remote Login, then: ssh mac-host ping"
fi
