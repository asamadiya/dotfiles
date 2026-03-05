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
    sed "s|__USER__|$(whoami)|g; s|__HOME__|$HOME|g" "$tpl" > "$dst"
    echo "  generated: $dst"
}

echo "=== Shell ==="
link "$DOTFILES/shell/bashrc"        "$HOME/.bashrc"
link "$DOTFILES/shell/bash_profile"  "$HOME/.bash_profile"
link "$DOTFILES/shell/profile"       "$HOME/.profile"

echo "=== Git ==="
link "$DOTFILES/git/gitconfig"       "$HOME/.gitconfig"

echo "=== Oh My Tmux ==="
if [ ! -d "$OHMYTMUX" ]; then
    git clone https://github.com/gpakosz/.tmux.git "$OHMYTMUX"
    echo "  installed: oh-my-tmux"
else
    echo "  exists: oh-my-tmux (pull to update)"
fi
link "$OHMYTMUX/.tmux.conf" "$HOME/.tmux.conf"
generate "$DOTFILES/tmux/tmux.conf.local.tpl" "$HOME/.tmux.conf.local"

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
