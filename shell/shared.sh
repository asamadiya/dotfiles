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

# authn-cli (godbus) dbus-launches an orphan session bus per call when none is set;
# each pins an inotify instance until the 1024 cap takes down systemd --user.
# Here rather than zshenv so bash (mosh/ssh login shells, cron) gets it too.
export DBUS_SESSION_BUS_ADDRESS=disabled:

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
