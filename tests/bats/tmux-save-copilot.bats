#!/usr/bin/env bats

load helpers

setup() {
  TMPHOME=$(mktemp -d)
  export HOME=$TMPHOME
  mkdir -p "$HOME/.tmux/resurrect"
  mkdir -p "$HOME/.copilot/session-state/abc-uuid"
  touch "$HOME/.copilot/session-state/abc-uuid/inuse.99999.lock"
}

teardown() { rm -rf "$TMPHOME"; }

@test "exits 0 when no resurrect/last present" {
  run "$DOTFILES_ROOT/bin/tmux-save-copilot-sessions"
  [ "$status" -eq 0 ]
}

@test "exits 0 when session-state dir absent" {
  rm -rf "$HOME/.copilot"
  run "$DOTFILES_ROOT/bin/tmux-save-copilot-sessions"
  [ "$status" -eq 0 ]
}
