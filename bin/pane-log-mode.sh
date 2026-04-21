#!/usr/bin/env bash
# pane-log-mode.sh — flip the /tmp/tmux-pane-log-mode-b sentinel.
set -eu
SENT=/tmp/tmux-pane-log-mode-b
if [[ -f "$SENT" ]]; then
  rm -f "$SENT"
  tmux display-message "pane-log mode B: OFF (globally)"
else
  : > "$SENT"
  tmux display-message "pane-log mode B: ON (shell panes auto-log; TUI panes auto-skip)"
fi
