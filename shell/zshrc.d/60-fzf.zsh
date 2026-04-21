# 60-fzf.zsh — fzf key bindings + completion.
# Ctrl-T: file picker. Alt-C: cd. Ctrl-R: handled by atuin (75-atuin.zsh).

if command -v fzf >/dev/null; then
  # fzf's shell integration scripts are fetched by bin/install-user-bins.sh
  # into ~/.local/share/fzf/ (they are not in the binary-only release tarball).
  for _fzf_src in \
    "$HOME/.local/share/fzf/key-bindings.zsh" \
    "$HOME/.fzf/shell/key-bindings.zsh"; do
    [[ -f "$_fzf_src" ]] && source "$_fzf_src" && break
  done
  for _fzf_comp in \
    "$HOME/.local/share/fzf/completion.zsh" \
    "$HOME/.fzf/shell/completion.zsh"; do
    [[ -f "$_fzf_comp" ]] && source "$_fzf_comp" && break
  done

  # Prefer fd for listings (faster, gitignore-aware)
  if command -v fd >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
  fi
fi
