#!/usr/bin/env bash
# pane-log-toggle.sh — flip tmux pipe-pane logging on/off for $TMUX_PANE.
# State tracked via a per-pane empty sentinel at /tmp/tmux-pane-log-active.<id>.

set -eu

pane="${TMUX_PANE:-}"
[[ -n "$pane" ]] || { echo "no TMUX_PANE"; exit 1; }

ID=${pane#%}
SENT="/tmp/tmux-pane-log-active.${ID}"
DAY=$(date +%Y/%m/%d)
LOG_DIR="$HOME/logs/tmux/$DAY"
mkdir -p "$LOG_DIR"

if [[ -f "$SENT" ]]; then
  tmux pipe-pane
  rm -f "$SENT"
  tmux display-message "pane logging: OFF ($pane)"
else
  LOG_FILE="$LOG_DIR/S-$(tmux display-message -p '#S')_W-$(tmux display-message -p '#I')_P-${ID}.log"
  tmux pipe-pane -o "cat >> $LOG_FILE"
  : > "$SENT"
  tmux display-message "pane logging: ON → $LOG_FILE"
fi
