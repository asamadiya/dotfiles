# Pane-logging mode B: auto-on for shell prompts, auto-off during known TUI commands.
# Toggled globally by /tmp/tmux-pane-log-mode-b sentinel.

_TUI_CMDS=(vim nvim htop btop lazygit less more watch top claude copilot man yazi broot)

_tui_check() {
  [[ -f /tmp/tmux-pane-log-mode-b ]] || return 1
  [[ -n ${TMUX_PANE:-} ]] || return 1
  local first=${1%% *}
  for c in ${_TUI_CMDS[@]}; do [[ $first == $c ]] && return 0; done
  return 1
}

_pane_log_on() {
  [[ -f /tmp/tmux-pane-log-mode-b ]] || return
  [[ -n ${TMUX_PANE:-} ]] || return
  local DAY=$(date +%Y/%m/%d)
  local LOG_DIR="$HOME/logs/tmux/$DAY"
  mkdir -p "$LOG_DIR"
  local LOG_FILE="$LOG_DIR/S-$(tmux display-message -p '#S')_W-$(tmux display-message -p '#I')_P-${TMUX_PANE#%}.log"
  tmux pipe-pane -o "cat >> $LOG_FILE"
}
_pane_log_off() { tmux pipe-pane 2>/dev/null || true; }

preexec() { if _tui_check "$1"; then _pane_log_off; fi }
precmd()  { _pane_log_on; }
