# 85-carapace.zsh — defer carapace's `source <(...)` to the first prompt,
# because it calls compdef which only exists after compinit has run, and
# compinit is turbo-loaded (runs AFTER zshrc.d modules complete).

if command -v carapace >/dev/null; then
  export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
  zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'

  autoload -Uz add-zsh-hook
  _carapace_load_once() {
    source <(carapace _carapace zsh)
    add-zsh-hook -d precmd _carapace_load_once
    unset -f _carapace_load_once
  }
  add-zsh-hook precmd _carapace_load_once
fi
