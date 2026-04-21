#!/usr/bin/env bats

load helpers

@test "sysstat.sh runs and prints a non-empty line" {
  run "$DOTFILES_ROOT/bin/sysstat.sh"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$output" == *"CPU "* ]]
  [[ "$output" == *"MEM "* ]]
  [[ "$output" == *"DISK "* ]]
  [[ "$output" == *"L "* ]]
}

@test "sysstat.sh omits GPU segment when /tmp/nvidia-stats is absent" {
  rm -f /tmp/nvidia-stats
  run "$DOTFILES_ROOT/bin/sysstat.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"GPU "* ]]
}

@test "sysstat.sh includes GPU segment when /tmp/nvidia-stats is fresh" {
  printf '42 2048 16384\n' > /tmp/nvidia-stats
  run "$DOTFILES_ROOT/bin/sysstat.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GPU 42% 2.0G/16.0G"* ]]
  rm -f /tmp/nvidia-stats
}

@test "sysstat.sh wall-time budget <= 200 ms" {
  start=$(date +%s%N)
  "$DOTFILES_ROOT/bin/sysstat.sh" >/dev/null
  end=$(date +%s%N)
  ms=$(( (end - start) / 1000000 ))
  [ "$ms" -lt 200 ]
}
