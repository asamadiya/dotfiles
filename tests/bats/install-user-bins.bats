#!/usr/bin/env bats

load helpers

@test "--help-like flag that isn't recognised errors with exit 2" {
  run "$DOTFILES_ROOT/bin/install-user-bins.sh" --nope
  [ "$status" -eq 2 ]
}

@test "registered fzf installs to BINDIR" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  BINDIR="$tmp" run "$DOTFILES_ROOT/bin/install-user-bins.sh" fzf
  [ "$status" -eq 0 ]
  [ -x "$tmp/fzf" ]
  "$tmp/fzf" --version | head -1
}

@test "unknown-tool arg fails cleanly" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  BINDIR="$tmp" run "$DOTFILES_ROOT/bin/install-user-bins.sh" not-a-tool
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool"* ]]
}

@test "second run with --force re-installs" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  BINDIR="$tmp" "$DOTFILES_ROOT/bin/install-user-bins.sh" fzf
  ts1=$(stat -c %Y "$tmp/fzf")
  sleep 1
  BINDIR="$tmp" run "$DOTFILES_ROOT/bin/install-user-bins.sh" --force fzf
  [ "$status" -eq 0 ]
  ts2=$(stat -c %Y "$tmp/fzf")
  [ "$ts2" -gt "$ts1" ]
}
