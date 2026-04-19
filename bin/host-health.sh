#!/usr/bin/env bash
# Emit a colored tmux status segment with 1-min load + MemAvailable.
# Designed to be wired as a #(...) segment in status-right, re-executed
# by tmux every status-interval. Colors match the catppuccin theme.
# Tune the thresholds below for the host.
#   RED   load > 30 or MemAvailable < 1G
#   YEL   load > 10 or MemAvailable < 4G
#   GRAY  otherwise (neutral)

set -eu

read _ load1 _ < /proc/loadavg
mem_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
mem_g=$(awk -v k="$mem_kb" 'BEGIN{printf "%.1f", k/1024/1024}')

load_int=${load1%%.*}
mem_int=${mem_g%%.*}

if   (( load_int > 30 )) || (( mem_int < 1 )); then
    pre='#[fg=#f38ba8,bold]'
elif (( load_int > 10 )) || (( mem_int < 4 )); then
    pre='#[fg=#f9e2af]'
else
    pre='#[fg=#a6adc8]'
fi

printf '%sL %s  M %sG#[default]' "$pre" "$load1" "$mem_g"
