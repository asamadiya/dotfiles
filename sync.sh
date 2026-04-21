#!/bin/bash
# Bidirectional dotfile sync.
# Usage:
#   ./sync.sh              # pull: live system -> repo (show diff)
#   ./sync.sh --commit     # pull + commit
#   ./sync.sh --push       # push: repo -> live system
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# ── Direct file mapping: live_path <-> repo_path ──
declare -A FILES=(
    ["$HOME/.bashrc"]="$DOTFILES/shell/bashrc"
    ["$HOME/.bash_profile"]="$DOTFILES/shell/bash_profile"
    ["$HOME/.profile"]="$DOTFILES/shell/profile"
    ["$HOME/.gitconfig"]="$DOTFILES/git/gitconfig"
    ["$HOME/.claude/keybindings.json"]="$DOTFILES/claude/keybindings.json"
    ["$HOME/.claude/rules/persona.md"]="$DOTFILES/claude/rules/persona.md"
    ["$HOME/CLAUDE.md"]="$DOTFILES/claude/CLAUDE.md"
    ["$HOME/.inputrc"]="$DOTFILES/shell/inputrc"
    ["$HOME/.vimrc"]="$DOTFILES/vim/vimrc"
    ["$HOME/.config/starship.toml"]="$DOTFILES/config/starship.toml"
)

# ── Template files: live_path <-> repo_template ──
# On pull: copy live file, replace $HOME with __HOME__, user with __USER__
# On push: replace __HOME__/__USER__ with actual values
declare -A TEMPLATES=(
    ["$HOME/.tmux.conf.local"]="$DOTFILES/tmux/tmux.conf.local.tpl"
    ["$HOME/.claude/settings.json"]="$DOTFILES/claude/settings.json.tpl"
    ["$HOME/.config/systemd/user/tmux.service"]="$DOTFILES/systemd/tmux.service.tpl"
)

BIN_SCRIPTS=(tmux-claude-restore tmux-save-claude-sessions tmux-restore keepalive.sh claude-guard-main.sh claude-statusline.sh lint-shell.sh lfs-template-apply sysstat.sh nvidia-daemon.sh tmux-save-copilot-sessions tmux-copilot-restore wt session-end-autocommit.sh copilot-with-autocommit state-snapshot.sh pane-log-toggle.sh pane-log-mode.sh install-user-bins.sh)

copy_if_exists() {
    local src="$1" dst="$2"
    if [ -f "$src" ] || [ -L "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        cp "$(readlink -f "$src")" "$dst"
        echo "  synced: $src -> $dst"
    else
        echo "  skip:   $src (not found)"
    fi
}

templatize() {
    # Replace actual $HOME and username with __HOME__ and __USER__
    local src="$1" dst="$2"
    if [ -f "$src" ] || [ -L "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        sed "s|$HOME|__HOME__|g; s|$(whoami)|__USER__|g" "$(readlink -f "$src")" > "$dst"
        echo "  synced: $src -> $dst (templatized)"
    else
        echo "  skip:   $src (not found)"
    fi
}

detemplatize() {
    # Replace __HOME__ and __USER__ with actual values
    local src="$1" dst="$2"
    if [ -f "$src" ]; then
        mkdir -p "$(dirname "$dst")"
        sed "s|__HOME__|$HOME|g; s|__USER__|$(whoami)|g" "$src" > "$dst"
        echo "  pushed: $src -> $dst (generated)"
    else
        echo "  skip:   $src (not in repo)"
    fi
}

pull() {
    echo "=== Pull: live system -> dotfiles repo ==="

    echo ""
    echo "-- Direct files --"
    for live in "${!FILES[@]}"; do
        copy_if_exists "$live" "${FILES[$live]}"
    done

    echo ""
    echo "-- Template files --"
    for live in "${!TEMPLATES[@]}"; do
        templatize "$live" "${TEMPLATES[$live]}"
    done

    echo ""
    echo "-- Scripts (~/bin) --"
    mkdir -p "$DOTFILES/bin"
    for script in "${BIN_SCRIPTS[@]}"; do
        copy_if_exists "$HOME/bin/$script" "$DOTFILES/bin/$script"
    done

    echo ""
    echo "-- Claude agents --"
    mkdir -p "$DOTFILES/claude/agents"
    for agent in "$HOME/.claude/agents/"*.md; do
        [ -f "$agent" ] && copy_if_exists "$agent" "$DOTFILES/claude/agents/$(basename "$agent")"
    done

    echo ""
    echo "=== Diff ==="
    cd "$DOTFILES"
    if ! git diff --quiet 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        git diff --stat
        echo ""
        git diff
        untracked=$(git ls-files --others --exclude-standard)
        if [ -n "$untracked" ]; then
            echo ""
            echo "Untracked files:"
            echo "$untracked" | sed 's/^/  /'
        fi
    else
        echo "  No changes detected."
    fi
}

push() {
    echo "=== Push: dotfiles repo -> live system ==="

    echo ""
    echo "-- Direct files --"
    for live in "${!FILES[@]}"; do
        repo="${FILES[$live]}"
        if [ -f "$repo" ]; then
            mkdir -p "$(dirname "$live")"
            [ -L "$live" ] && rm "$live"
            [ -f "$live" ] && ! [ -L "$live" ] && mv "$live" "${live}.bak" && echo "  backup: $live"
            cp "$repo" "$live"
            echo "  pushed: $repo -> $live"
        fi
    done

    echo ""
    echo "-- Template files --"
    for live in "${!TEMPLATES[@]}"; do
        detemplatize "${TEMPLATES[$live]}" "$live"
    done

    echo ""
    echo "-- Scripts (~/bin) --"
    mkdir -p "$HOME/bin"
    for script in "$DOTFILES/bin/"*; do
        name=$(basename "$script")
        [ -L "$HOME/bin/$name" ] && rm "$HOME/bin/$name"
        [ -f "$HOME/bin/$name" ] && mv "$HOME/bin/$name" "$HOME/bin/${name}.bak"
        cp "$script" "$HOME/bin/$name"
        chmod +x "$HOME/bin/$name"
        echo "  pushed: $script -> $HOME/bin/$name"
    done

    echo ""
    echo "-- Claude agents --"
    mkdir -p "$HOME/.claude/agents"
    for agent in "$DOTFILES/claude/agents/"*.md; do
        [ -f "$agent" ] || continue
        cp "$agent" "$HOME/.claude/agents/$(basename "$agent")"
        echo "  pushed: $agent -> $HOME/.claude/agents/$(basename "$agent")"
    done

    echo ""
    echo "-- Systemd reload --"
    systemctl --user daemon-reload 2>/dev/null && echo "  reloaded systemd" || echo "  skip: systemd"

    echo ""
    echo "Done. Reload shell: source ~/.bash_profile"
}

case "${1:-}" in
    --push)
        push
        ;;
    --commit)
        pull
        if cd "$DOTFILES" && ! git diff --quiet 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
            echo ""
            echo "=== Committing ==="
            git add -A
            git commit -m "Sync dotfiles from live system ($(date +%Y-%m-%d))"
            echo "Done."
        else
            echo ""
            echo "Nothing to commit."
        fi
        ;;
    --help|-h)
        echo "Usage: $(basename "$0") [option]"
        echo ""
        echo "  (no args)    Pull: live system -> repo (show diff)"
        echo "  --commit     Pull + auto-commit"
        echo "  --push       Push: repo -> live system"
        echo "  --help       This message"
        ;;
    *)
        pull
        ;;
esac
