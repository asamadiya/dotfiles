#!/usr/bin/env bash
# Unified tmux status-right segment: CPU% · MEM · DISK · GPU · load.
# Replaces bin/host-health.sh.
# Runs in ~20 ms wall; safe at 5s status-interval.
# GPU segment is silent when /tmp/nvidia-stats is absent or stale >30s (spec §4.4).

set -eu

STATE_DIR="${TMPDIR:-/tmp}"
CPU_STATE="$STATE_DIR/sysstat.cpu.state"
NVIDIA_STATS="$STATE_DIR/nvidia-stats"

# --- palette (catppuccin) -----------------------------------------------------
C_OK='#[fg=#a6adc8]'     # subtext0
C_WARN='#[fg=#f9e2af]'   # yellow
C_CRIT='#[fg=#f38ba8,bold]'  # red
C_RST='#[default]'

colorize() {
  local val="$1" warn="$2" crit="$3" pre
  if   (( val >= crit )); then pre=$C_CRIT
  elif (( val >= warn )); then pre=$C_WARN
  else pre=$C_OK; fi
  printf '%s' "$pre"
}

# --- CPU % --------------------------------------------------------------------
read_cpu() {
  # /proc/stat first line: cpu user nice system idle iowait irq softirq steal ...
  read -ra cur < /proc/stat
  local user=${cur[1]} nice=${cur[2]} sys=${cur[3]} idle=${cur[4]} iow=${cur[5]} \
        irq=${cur[6]} sirq=${cur[7]} steal=${cur[8]:-0}
  local non_idle=$((user + nice + sys + irq + sirq + steal))
  local total=$((non_idle + idle + iow))

  local pct=0
  if [[ -f $CPU_STATE ]]; then
    read -r prev_total prev_non_idle < "$CPU_STATE"
    local dt=$((total - prev_total))
    local dni=$((non_idle - prev_non_idle))
    if (( dt > 0 )); then
      pct=$(( 100 * dni / dt ))
    fi
  fi
  printf '%d %d\n' "$total" "$non_idle" > "$CPU_STATE"
  printf '%d' "$pct"
}

# --- MEM ----------------------------------------------------------------------
read_mem() {
  awk '
    /^MemTotal:/     { total = $2 }
    /^MemAvailable:/ { avail = $2 }
    END {
      used = total - avail
      used_pct = (total > 0) ? int(100 * used / total) : 0
      total_g = total / 1024 / 1024
      used_g  = used / 1024 / 1024
      printf "%d %.0f %.0f\n", used_pct, used_g, total_g
    }
  ' /proc/meminfo
}

# --- DISK (/) -----------------------------------------------------------------
read_disk() {
  # timeout guards against hung mounts; single fork.
  timeout 1s df -P / 2>/dev/null | awk 'NR==2 { sub(/%/, "", $5); print $5 }'
}

# --- GPU ----------------------------------------------------------------------
read_gpu() {
  # /tmp/nvidia-stats is "util, used_mib, total_mib" written by bin/nvidia-daemon.sh.
  if [[ ! -f $NVIDIA_STATS ]]; then return 1; fi
  local mtime
  mtime=$(stat -c %Y "$NVIDIA_STATS")
  local now; now=$(date +%s)
  (( now - mtime < 30 )) || return 1
  read -r util used total < "$NVIDIA_STATS"
  printf '%d %.1f %.1f' "$util" "$(awk "BEGIN{print $used/1024}")" "$(awk "BEGIN{print $total/1024}")"
}

# --- Load ---------------------------------------------------------------------
read_load() { read -r l1 _ _ _ < /proc/loadavg; printf '%s' "$l1"; }

# --- render -------------------------------------------------------------------
cpu_pct=$(read_cpu)
read -r mem_pct mem_used mem_total < <(read_mem)
disk_pct=$(read_disk)
disk_pct=${disk_pct:-0}
load1=$(read_load)
load_int=${load1%%.*}

cpu_col=$(colorize "$cpu_pct" 50 80)
mem_col=$(colorize "$mem_pct" 75 90)             # used%: warn at 75, crit at 90
disk_col=$(colorize "$disk_pct" 80 95)
load_col=$(colorize "$load_int" 10 30)

out="${cpu_col}CPU ${cpu_pct}%${C_RST} · "
out+="${mem_col}MEM ${mem_used}G/${mem_total}G (${mem_pct}%)${C_RST} · "
out+="${disk_col}DISK ${disk_pct}%${C_RST}"

if gpu_line=$(read_gpu 2>/dev/null); then
  read -r gutil gused gtotal <<< "$gpu_line"
  gpu_col=$(colorize "$gutil" 70 90)
  out+=" · ${gpu_col}GPU ${gutil}% ${gused}G/${gtotal}G${C_RST}"
fi

out+=" · ${load_col}L ${load1}${C_RST}"

printf '%s' "$out"
