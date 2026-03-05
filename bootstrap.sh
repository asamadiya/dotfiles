#!/bin/bash
# Bootstrap script — installs prerequisites and sets up the full environment.
# Run on a fresh VM to recreate the exact dev experience.
# Usage: ./bootstrap.sh
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
LOCAL="$HOME/.local"
mkdir -p "$LOCAL/bin" "$LOCAL/lib" "$LOCAL/include"

log() { echo -e "\033[1;34m==> $*\033[0m"; }
warn() { echo -e "\033[1;33m  ! $*\033[0m"; }
ok() { echo -e "\033[1;32m  ✓ $*\033[0m"; }

# ── System package check ──
log "Checking system packages"
MISSING=()
for cmd in git gcc make autoconf automake pkg-config curl jq python3 node; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    warn "Missing: ${MISSING[*]}"
    if command -v sudo &>/dev/null; then
        if command -v tdnf &>/dev/null; then
            log "Installing via tdnf"
            sudo tdnf install -y "${MISSING[@]}" || warn "Some packages failed — install manually"
        elif command -v apt-get &>/dev/null; then
            log "Installing via apt"
            sudo apt-get update && sudo apt-get install -y "${MISSING[@]}" || warn "Some packages failed"
        elif command -v yum &>/dev/null; then
            log "Installing via yum"
            sudo yum install -y "${MISSING[@]}" || warn "Some packages failed"
        fi
    else
        warn "No sudo — install these manually: ${MISSING[*]}"
    fi
fi

# ── xclip (clipboard for tmux) ──
if ! command -v xclip &>/dev/null; then
    log "Installing xclip"
    if command -v sudo &>/dev/null; then
        sudo tdnf install -y xclip 2>/dev/null || \
        sudo apt-get install -y xclip 2>/dev/null || \
        sudo yum install -y xclip 2>/dev/null || \
        warn "Could not install xclip — tmux clipboard won't work"
    else
        warn "No sudo — install xclip manually for tmux clipboard support"
    fi
fi

# ── libevent (tmux build dependency) ──
LIBEVENT_VER="2.1.12"
if [ ! -f "$LOCAL/lib/libevent.so" ] && [ ! -f "$LOCAL/lib/libevent-2.1.so.7" ]; then
    log "Building libevent $LIBEVENT_VER"
    cd /tmp
    curl -fsSL "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VER}-stable/libevent-${LIBEVENT_VER}-stable.tar.gz" | tar xz
    cd "libevent-${LIBEVENT_VER}-stable"
    ./configure --prefix="$LOCAL" --disable-openssl 2>&1 | tail -1
    make -j"$(nproc)" 2>&1 | tail -1
    make install 2>&1 | tail -1
    ok "libevent $LIBEVENT_VER"
    cd /tmp && rm -rf "libevent-${LIBEVENT_VER}-stable"
else
    ok "libevent already installed"
fi

# ── tmux 3.5a (from source) ──
TMUX_VER="3.5a"
TMUX_BIN="$LOCAL/bin/tmux"
if [ -x "$TMUX_BIN" ] && "$TMUX_BIN" -V 2>/dev/null | grep -q "$TMUX_VER"; then
    ok "tmux $TMUX_VER already installed"
else
    log "Building tmux $TMUX_VER"
    cd /tmp
    curl -fsSL "https://github.com/tmux/tmux/releases/download/${TMUX_VER}/tmux-${TMUX_VER}.tar.gz" | tar xz
    cd "tmux-${TMUX_VER}"
    PKG_CONFIG_PATH="$LOCAL/lib/pkgconfig" \
    CFLAGS="-I$LOCAL/include" \
    LDFLAGS="-L$LOCAL/lib -Wl,-rpath,$LOCAL/lib" \
    YACC="true" \
    ./configure --prefix="$LOCAL" 2>&1 | tail -1
    make -j"$(nproc)" 2>&1 | tail -1
    make install 2>&1 | tail -1
    ok "tmux $TMUX_VER -> $TMUX_BIN"
    cd /tmp && rm -rf "tmux-${TMUX_VER}"
fi

# ── oh-my-tmux ──
OHMYTMUX="$HOME/oh-my-tmux"
if [ ! -d "$OHMYTMUX" ]; then
    log "Cloning oh-my-tmux"
    git clone https://github.com/gpakosz/.tmux.git "$OHMYTMUX"
    ok "oh-my-tmux"
else
    ok "oh-my-tmux already cloned"
fi

# ── Claude Code ──
if ! command -v claude &>/dev/null; then
    log "Installing Claude Code"
    if command -v npm &>/dev/null; then
        npm install -g @anthropic-ai/claude-code 2>&1 | tail -1
        ok "Claude Code installed"
    else
        warn "npm not found — install Claude Code manually: npm install -g @anthropic-ai/claude-code"
    fi
else
    ok "Claude Code $(claude --version 2>/dev/null || echo 'installed')"
fi

# ── TPM (tmux plugin manager) ──
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
    log "Installing TPM"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    ok "TPM"
else
    ok "TPM already installed"
fi

# ── Install dotfiles ──
log "Running dotfiles installer"
"$DOTFILES/install.sh"

# ── Install tmux plugins ──
log "Installing tmux plugins"
"$TPM_DIR/bin/install_plugins" 2>&1 | tail -3
ok "tmux plugins"

# ── Start keepalive ──
if ! pgrep -f keepalive.sh &>/dev/null; then
    log "Starting keepalive daemon"
    nohup "$HOME/bin/keepalive.sh" > /dev/null 2>&1 &
    ok "keepalive (PID: $!)"
fi

# ── Verify ──
log "Verification"
echo "  tmux:    $($TMUX_BIN -V)"
echo "  git:     $(git --version)"
echo "  python:  $(python3 --version)"
echo "  node:    $(node --version)"
echo "  jq:      $(jq --version)"
echo "  claude:  $(claude --version 2>/dev/null || echo 'run claude to login')"
echo "  xclip:   $(xclip -version 2>&1 | head -1 || echo 'not installed')"
echo ""
log "Done. Start tmux: $TMUX_BIN"
echo "  Then press prefix+I to finalize plugin install."
echo "  Reload shell: source ~/.bash_profile"
