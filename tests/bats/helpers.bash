#!/usr/bin/env bash
# Shared bats helpers used by all tests under tests/bats/.

# Absolute path to the dotfiles repo root.
DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DOTFILES_ROOT

# Path to a script in bin/ relative to repo root.
bin_path() { printf '%s/bin/%s' "$DOTFILES_ROOT" "$1"; }

# Run a script and capture both stdout and exit code into the bats $output / $status.
# Usage inside a test: run_script sysstat.sh; [ "$status" -eq 0 ]
run_script() { run bash "$(bin_path "$1")" "${@:2}"; }
