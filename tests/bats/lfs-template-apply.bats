#!/usr/bin/env bats

load helpers

setup() {
  tmp=$(mktemp -d)
  (cd "$tmp" && git init -q)
}

teardown() { rm -rf "$tmp"; }

@test "applies all patterns to empty repo" {
  run "$DOTFILES_ROOT/bin/lfs-template-apply" "$tmp"
  [ "$status" -eq 0 ]
  grep -qxF '*.age filter=lfs diff=lfs merge=lfs -text' "$tmp/.gitattributes"
  grep -qxF '*.pdf filter=lfs diff=lfs merge=lfs -text' "$tmp/.gitattributes"
}

@test "is idempotent (second run adds nothing)" {
  "$DOTFILES_ROOT/bin/lfs-template-apply" "$tmp"
  before=$(wc -l < "$tmp/.gitattributes")
  run "$DOTFILES_ROOT/bin/lfs-template-apply" "$tmp"
  [ "$status" -eq 0 ]
  after=$(wc -l < "$tmp/.gitattributes")
  [ "$before" -eq "$after" ]
}

@test "preserves existing user rules" {
  printf '*.customext filter=special\n' > "$tmp/.gitattributes"
  run "$DOTFILES_ROOT/bin/lfs-template-apply" "$tmp"
  [ "$status" -eq 0 ]
  grep -qxF '*.customext filter=special' "$tmp/.gitattributes"
  grep -qxF '*.age filter=lfs diff=lfs merge=lfs -text' "$tmp/.gitattributes"
}

@test "fails cleanly on non-repo path" {
  run "$DOTFILES_ROOT/bin/lfs-template-apply" /tmp
  [ "$status" -eq 2 ]
}
