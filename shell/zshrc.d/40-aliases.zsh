# 40-aliases.zsh — aliases. Escape any with a leading backslash to reach the
# original command (e.g. \ls, \cat). `grep` is intentionally NOT aliased to rg
# per user preference — muscle-memory on unknown hosts.

# Claude / Copilot / kube (ported from bash)
alias c='claude'
alias cc='claude --continue'
alias cr='claude --resume'
alias cw='claude --worktree'
alias cp='copilot'
alias k='kubectl'

# Git
alias lg='lazygit'
alias gst='git status'
alias gd='git diff'
alias glg='git log --graph --oneline --all --decorate'
alias gfix='git absorb --and-rebase'
alias gdft='GIT_EXTERNAL_DIFF=difft git log -p --ext-diff'

# Modern CLI overrides (with \<cmd> escape to reach original)
alias ls='eza --icons'
alias ll='eza -lah --icons --git'
alias la='eza -a --icons'
alias lt='eza --tree --level=2 --icons'
alias cat='bat -p'

# Stats / inspection
alias clx='scc .'
alias dush='dust'
alias dfh='duf'
alias psh='procs'

# Recording
alias rec='asciinema rec'

# LazyVim (via NVIM_APPNAME for isolation) — added in Task 22
alias lv='NVIM_APPNAME=nvim-lazy nvim'
