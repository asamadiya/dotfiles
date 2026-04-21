#!/usr/bin/env bats

load helpers

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q -b master
  git config user.email t@t; git config user.name t
  git commit --allow-empty -q -m init
}

teardown() { cd /; rm -rf "$TMP"; }

@test "no-op when clean working tree" {
  run "$DOTFILES_ROOT/bin/session-end-autocommit.sh" claude deadbeef
  [ "$status" -eq 0 ]
  [ "$(git log --oneline | wc -l)" -eq 1 ]
}

@test "commits working changes with clean summary" {
  echo "hello" > foo.txt
  run "$DOTFILES_ROOT/bin/session-end-autocommit.sh" claude deadbeef
  [ "$status" -eq 0 ]
  [ "$(git log --oneline | wc -l)" -eq 2 ]
  git log -1 --pretty=%B | grep -qE 'session claude deadbeef'
}

@test "no Co-Authored-By in the message" {
  echo "x" > foo.txt
  "$DOTFILES_ROOT/bin/session-end-autocommit.sh" claude deadbeef
  ! git log -1 --pretty=%B | grep -qi 'Co-Authored-By'
}

@test "aborts on ghp_ token" {
  echo "my key is ghp_abcdefghijklmnop1234" > leak.txt
  run "$DOTFILES_ROOT/bin/session-end-autocommit.sh" claude deadbeef
  [ "$status" -eq 2 ]
  [ "$(git log --oneline | wc -l)" -eq 1 ]
}
