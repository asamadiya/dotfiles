# 85-carapace.zsh — source carapace's completion definitions, running compinit
# synchronously first so compdef exists when carapace calls it.
#
# Background: zinit turbo schedules `zicompinit` via the fast-syntax-highlighting
# plugin's atinit hook, which fires AFTER the first prompt is drawn. Our previous
# attempt (defer via precmd hook) raced — precmd can fire before turbo-scheduled
# compinit completes, leaving compdef undefined when carapace sources its script.
# The fix: run compinit ourselves if it hasn't run yet. compinit on a warm cache
# is cheap (~5 ms); zinit's later zicompinit is a no-op at that point.

if command -v carapace >/dev/null; then
  export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
  zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'

  if ! whence compdef >/dev/null 2>&1; then
    autoload -Uz compinit
    compinit -u
  fi

  source <(carapace _carapace zsh)
fi
