#!/bin/bash
# Power-user statusline for Claude Code
# Shows: model | git branch | dir | GPU | load | cost | context bar
# Receives JSON on stdin from Claude Code

INPUT=$(cat)

# Parse fields from JSON
MODEL=$(jq -r '.model.display_name // "Claude"' <<<"$INPUT" 2>/dev/null)
DIR=$(jq -r '.workspace.current_dir // empty' <<<"$INPUT" 2>/dev/null)
DIR=${DIR:-$(pwd)}
DIRNAME=$(basename "$DIR")
REMAINING=$(jq -r '.context_window.remaining_percentage // empty' <<<"$INPUT" 2>/dev/null)
COST=$(jq -r '.estimated_cost // .cost.total_cost_usd // empty' <<<"$INPUT" 2>/dev/null)

# Git branch + dirty glyph (fast, no fork if not in repo)
BRANCH=""
DIRTY=""
if [ -d "$DIR/.git" ] || git -C "$DIR" rev-parse --git-dir &>/dev/null; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
    if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null | head -1)" ]; then
        DIRTY="*"
    fi
fi

# GPU utilization (cached, refreshed every 10s)
GPU_CACHE="/tmp/claude-gpu-status"
if [ ! -f "$GPU_CACHE" ] || [ $(($(date +%s) - $(stat -c %Y "$GPU_CACHE" 2>/dev/null || echo 0))) -gt 10 ]; then
    nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | awk -F', ' '{printf "GPU:%s%% %sM/%sM", $1, $2, $3}' > "$GPU_CACHE" 2>/dev/null
fi
GPU=$(cat "$GPU_CACHE" 2>/dev/null)

# Load average (1min)
LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)

# Context bar (10 segments, color-coded)
CTX=""
if [ -n "$REMAINING" ]; then
    USED=$(echo "$REMAINING" | awk '{
        usable = ($1 - 16.5) / (100 - 16.5) * 100;
        if (usable < 0) usable = 0;
        used = 100 - usable;
        if (used < 0) used = 0;
        if (used > 100) used = 100;
        printf "%d", used
    }')
    FILLED=$((USED / 10))
    EMPTY=$((10 - FILLED))
    BAR=$(printf '█%.0s' $(seq 1 $FILLED 2>/dev/null))$(printf '░%.0s' $(seq 1 $EMPTY 2>/dev/null))

    if [ "$USED" -lt 50 ]; then
        CTX="\033[32m${BAR} ${USED}%\033[0m"
    elif [ "$USED" -lt 65 ]; then
        CTX="\033[33m${BAR} ${USED}%\033[0m"
    elif [ "$USED" -lt 80 ]; then
        CTX="\033[38;5;208m${BAR} ${USED}%\033[0m"
    else
        CTX="\033[5;31m${BAR} ${USED}%\033[0m"
    fi
fi

# Cost display
COST_STR=""
if [ -n "$COST" ] && [ "$COST" != "null" ]; then
    COST_STR="\033[2m\$${COST}\033[0m"
fi

# Build output
OUT="\033[2m${MODEL}\033[0m"
[ -n "$BRANCH" ] && OUT="${OUT} \033[36m${BRANCH}${DIRTY}\033[0m"
OUT="${OUT} \033[2m${DIRNAME}\033[0m"
[ -n "$GPU" ] && OUT="${OUT} \033[35m${GPU}\033[0m"
[ -n "$LOAD" ] && OUT="${OUT} \033[2mL:${LOAD}\033[0m"
[ -n "$COST_STR" ] && OUT="${OUT} ${COST_STR}"
[ -n "$CTX" ] && OUT="${OUT} ${CTX}"

printf "%b" "$OUT"
