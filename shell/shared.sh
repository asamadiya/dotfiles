# shell/shared.sh — shell-agnostic env exports sourced by both bash and zsh.
# Keep this POSIX-compatible (no [[ ]], no arrays, no zsh-isms).

# PATH additions (idempotent — guard against duplicates)
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) export PATH="$HOME/bin:$PATH" ;;
esac

# Core env
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LESS="-FRSX"
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# FZF
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --info=inline"

# bat as manpager (once bat is installed; guarded)
if command -v bat >/dev/null 2>&1; then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
