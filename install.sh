#!/bin/bash
# Dotfiles installer — generates configs from templates and symlinks into place.
# Run bootstrap.sh first to install prerequisites.
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
OHMYTMUX="$HOME/oh-my-tmux"

link() {
    local src="$1" dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo "  backup: $dst -> ${dst}.bak"
        mv "$dst" "${dst}.bak"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
    echo "  linked: $dst -> $src"
}

generate() {
    local tpl="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    sed "s|__USER__|$(whoami)|g; s|__HOME__|$HOME|g" "$tpl" > "$dst"
    echo "  generated: $dst"
}

echo "=== Shell ==="
link "$DOTFILES/shell/bashrc"        "$HOME/.bashrc"
link "$DOTFILES/shell/bash_profile"  "$HOME/.bash_profile"
link "$DOTFILES/shell/profile"       "$HOME/.profile"
link "$DOTFILES/shell/inputrc"       "$HOME/.inputrc"
mkdir -p "$HOME/.zshrc.d"
link "$DOTFILES/shell/zshrc.d/95-pane-log.zsh" "$HOME/.zshrc.d/95-pane-log.zsh"

echo "=== Vim ==="
link "$DOTFILES/vim/vimrc"           "$HOME/.vimrc"
mkdir -p "$HOME/.vim/undodir"

echo "=== Git ==="
link "$DOTFILES/git/gitconfig"          "$HOME/.gitconfig"
link "$DOTFILES/git/gitconfig-personal" "$HOME/.gitconfig-personal"
if [ ! -f "$HOME/.gitconfig-work" ]; then
  echo "Note: copy $DOTFILES/git/gitconfig-work.example to ~/.gitconfig-work and fill in your work email."
fi

echo "=== Oh My Tmux ==="
if [ ! -d "$OHMYTMUX" ]; then
    git clone https://github.com/gpakosz/.tmux.git "$OHMYTMUX"
    echo "  installed: oh-my-tmux"
else
    echo "  exists: oh-my-tmux (pull to update)"
fi
link "$OHMYTMUX/.tmux.conf" "$HOME/.tmux.conf"
generate "$DOTFILES/tmux/tmux.conf.local.tpl" "$HOME/.tmux.conf.local"

echo "=== Starship ==="
mkdir -p "$HOME/.config"
link "$DOTFILES/config/starship.toml" "$HOME/.config/starship.toml"

echo "=== Scripts ==="
mkdir -p "$HOME/bin"
for script in "$DOTFILES/bin/"*; do
    name=$(basename "$script")
    link "$script" "$HOME/bin/$name"
done

echo "=== Systemd user service ==="
mkdir -p "$HOME/.config/systemd/user"
generate "$DOTFILES/systemd/tmux.service.tpl" "$HOME/.config/systemd/user/tmux.service"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable tmux.service 2>/dev/null && echo "  enabled: tmux.service" || echo "  skip: systemd not available"

# --- nvidia-daemon (only if driver detected) ---
if [ -d /proc/driver/nvidia ]; then
  generate "$DOTFILES/systemd/nvidia-daemon.service.tpl" "$HOME/.config/systemd/user/nvidia-daemon.service"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now nvidia-daemon.service 2>/dev/null && echo "  enabled: nvidia-daemon.service" || echo "  skip: systemd not available"
else
  echo "  nvidia-daemon: NVIDIA driver absent, skipping service install"
fi

# --- state-snapshot (hourly state-repo snapshot, commit-only) ---
generate "$DOTFILES/systemd/state-snapshot.service.tpl" "$HOME/.config/systemd/user/state-snapshot.service"
generate "$DOTFILES/systemd/state-snapshot.timer.tpl"   "$HOME/.config/systemd/user/state-snapshot.timer"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now state-snapshot.timer 2>/dev/null && echo "  enabled: state-snapshot.timer" || echo "  skip: systemd not available"

# --- logrotate for ~/logs/tmux/ (guarded: sudo needed, skip silently otherwise) ---
if [ -w /etc/logrotate.d ] 2>/dev/null; then
  cp "$DOTFILES/config/logrotate/tmux-logs" /etc/logrotate.d/tmux-logs && echo "  installed: /etc/logrotate.d/tmux-logs"
elif sudo -n true 2>/dev/null; then
  sudo cp "$DOTFILES/config/logrotate/tmux-logs" /etc/logrotate.d/tmux-logs && echo "  installed (sudo): /etc/logrotate.d/tmux-logs"
else
  echo "  logrotate: run manually when convenient: sudo cp $DOTFILES/config/logrotate/tmux-logs /etc/logrotate.d/tmux-logs"
fi

echo "=== Copilot CLI ==="
mkdir -p "$HOME/.copilot"
link "$DOTFILES/config/copilot/statusline-settings.json" "$HOME/.copilot/statusline-settings.json"

echo "=== Claude Code ==="
mkdir -p "$HOME/.claude/rules" "$HOME/.claude/agents"
generate "$DOTFILES/claude/settings.json.tpl" "$HOME/.claude/settings.json"
link "$DOTFILES/claude/keybindings.json" "$HOME/.claude/keybindings.json"
link "$DOTFILES/claude/rules/persona.md" "$HOME/.claude/rules/persona.md"
link "$DOTFILES/claude/CLAUDE.md"        "$HOME/CLAUDE.md"
for agent in "$DOTFILES/claude/agents/"*.md; do
    [ -f "$agent" ] && link "$agent" "$HOME/.claude/agents/$(basename "$agent")"
done

echo ""
echo "Done. Start tmux: ~/.local/bin/tmux"
echo "  Press prefix+I to install tmux plugins."
echo "  Reload shell: source ~/.bash_profile"
