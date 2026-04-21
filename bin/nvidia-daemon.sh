#!/usr/bin/env bash
# Cache nvidia-smi GPU telemetry to /tmp/nvidia-stats every 2s.
# Silent exit if driver missing (no /proc/driver/nvidia or no nvidia-smi).

set -eu

OUT="${TMPDIR:-/tmp}/nvidia-stats"
INTERVAL="${NVIDIA_DAEMON_INTERVAL:-2}"

if [[ ! -d /proc/driver/nvidia ]] || ! command -v nvidia-smi >/dev/null; then
  echo "nvidia-daemon: NVIDIA driver not present; exiting cleanly"
  exit 0
fi

# -l<N> makes nvidia-smi poll every N seconds and emit one line each.
# We write a tmpfile and atomically rename so readers never see partial lines.
exec nvidia-smi \
  --query-gpu=utilization.gpu,memory.used,memory.total \
  --format=csv,noheader,nounits \
  -l "$INTERVAL" | while IFS= read -r line; do
  # Normalise "42, 2048, 16384" → "42 2048 16384"
  printf '%s\n' "$line" | tr -d ',' > "${OUT}.tmp"
  mv "${OUT}.tmp" "$OUT"
done
