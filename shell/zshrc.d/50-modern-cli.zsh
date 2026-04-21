# 50-modern-cli.zsh — tuning for bat/eza/fd/rg/delta.

# bat
if command -v bat >/dev/null; then
  export BAT_THEME="Catppuccin Mocha"
  export BAT_STYLE="numbers,changes,header"
fi

# eza — used via aliases; nothing to export here (icons inline via alias).

# fd — no env needed; honor .gitignore by default.

# ripgrep
if command -v rg >/dev/null; then
  export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
  if [[ ! -f "$RIPGREP_CONFIG_PATH" ]]; then
    mkdir -p "$HOME/.config/ripgrep"
    cat > "$RIPGREP_CONFIG_PATH" <<'EOF'
--smart-case
--max-columns=200
--glob=!.git/*
--glob=!*.lock
EOF
  fi
fi

# delta — honored by git via git/gitconfig (no env needed).
