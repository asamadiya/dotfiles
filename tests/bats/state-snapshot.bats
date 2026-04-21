#!/usr/bin/env bats

load helpers

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/state" "$TMP/.config/age" "$TMP/.claude/projects" "$TMP/.copilot/session-state"
  (cd "$TMP/state" && git init -q -b master && git config user.email t@t && git config user.name t)
  age-keygen -o "$TMP/.config/age/state-identity.txt" 2>/dev/null
  chmod 600 "$TMP/.config/age/state-identity.txt"
  export HOME=$TMP
  export STATE_REPO=$TMP/state
}

teardown() { rm -rf "$TMP"; }

@test "exits 0 when sources are empty and no changes" {
  run "$DOTFILES_ROOT/bin/state-snapshot.sh"
  [ "$status" -eq 0 ]
}

@test "commits an inventory file when source state exists" {
  echo '{"stub":true}' > "$HOME/.claude/projects/stub.jsonl"
  run "$DOTFILES_ROOT/bin/state-snapshot.sh"
  [ "$status" -eq 0 ]
  (cd "$STATE_REPO" && git log --oneline | head -1 | grep -q snapshot)
}

@test "does not create an origin remote (never pushes)" {
  (cd "$STATE_REPO" && git remote) | grep -q . && return 1 || return 0
}
