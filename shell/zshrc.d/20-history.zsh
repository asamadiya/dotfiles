# 20-history.zsh — zsh history settings.
# atuin takes over Ctrl-R below (75-atuin.zsh); this keeps the baseline
# plain-zsh history sane for up-arrow and non-atuin paths.

HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt APPEND_HISTORY            # multiple sessions append, not overwrite
setopt INC_APPEND_HISTORY        # incremental write (not just on exit)
setopt SHARE_HISTORY             # share new entries across running sessions
setopt HIST_IGNORE_DUPS          # don't record immediately-duplicated cmds
setopt HIST_IGNORE_ALL_DUPS      # remove older duplicates
setopt HIST_IGNORE_SPACE         # commands starting with space aren't saved
setopt HIST_REDUCE_BLANKS        # strip superfluous whitespace
setopt HIST_VERIFY               # don't exec !<hist> verbatim — confirm first
setopt EXTENDED_HISTORY          # timestamp + duration in history file
