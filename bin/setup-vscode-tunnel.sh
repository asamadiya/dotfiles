#!/usr/bin/env bash
# setup-vscode-tunnel.sh — install the VS Code CLI on this VM and start a
# persistent tunnel so the Mac can connect via the "Remote Tunnels" extension.
#
# Idempotent — safe to re-run after a CLI bump or to repair the systemd unit.
#
# Usage:
#   setup-vscode-tunnel.sh                 # tunnel name = $(hostname -s)
#   setup-vscode-tunnel.sh <tunnel-name>

set -euo pipefail

PREFIX="$HOME/.local/bin"
CODE="$PREFIX/code"
TUNNEL_NAME="${1:-$(hostname -s)}"

case "$(uname -m)" in
  x86_64)         BUILD=cli-alpine-x64 ;;
  aarch64|arm64)  BUILD=cli-alpine-arm64 ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$PREFIX"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo ">> downloading VS Code CLI ($BUILD)"
curl -fsSL -o "$tmp/code.tar.gz" \
  "https://code.visualstudio.com/sha/download?build=stable&os=$BUILD"
tar -xzf "$tmp/code.tar.gz" -C "$tmp"
install -m 0755 "$tmp/code" "$CODE"
echo ">> installed: $("$CODE" --version | head -1)"

if ! "$CODE" tunnel user show 2>/dev/null | grep -qi 'logged in'; then
  echo
  echo ">> logging in to GitHub — open the URL printed below and enter the code"
  "$CODE" tunnel user login --provider github
fi

echo
echo ">> renaming tunnel to: $TUNNEL_NAME"
"$CODE" tunnel rename "$TUNNEL_NAME" || true

echo
echo ">> installing tunnel as a systemd user service"
"$CODE" tunnel service install

echo
echo ">> tunnel status:"
"$CODE" tunnel status 2>&1 | head -20 || true

cat <<EOF

Done. From your Mac:
  Cmd+Shift+P -> Remote Tunnels: Connect to Tunnel... -> $TUNNEL_NAME

If the tunnel name doesn't appear, check that the same GitHub account is
signed in on both ends and that the service is running:
  systemctl --user status code-tunnel
EOF
