#!/usr/bin/env bats

load helpers

setup() {
  FAKE_HOME=$(mktemp -d)
  export HOME=$FAKE_HOME
  mkdir -p "$HOME/lin_code"
  (cd "$HOME/lin_code" && mkdir repoA && cd repoA && git init -q -b master && \
    git -c user.email=t@t -c user.name=t commit --allow-empty -q -m init)
}

teardown() { rm -rf "$FAKE_HOME"; }

@test "wt refuses outside ~/lin_code" {
  mkdir "$HOME/elsewhere"
  cd "$HOME/elsewhere"
  (cd "$HOME/elsewhere" && git init -q)
  run "$DOTFILES_ROOT/bin/wt" add feature-x
  [ "$status" -ne 0 ]
  [[ "$output" == *"only operates under"* ]]
}

@test "wt add creates worktree under wt/repoA/" {
  cd "$HOME/lin_code/repoA"
  TMUX= run "$DOTFILES_ROOT/bin/wt" add feature-x
  [ "$status" -eq 0 ]
  [ -d "$HOME/lin_code/wt/repoA/feature-x" ]
}

@test "wt ls lists an added worktree" {
  cd "$HOME/lin_code/repoA"
  TMUX= "$DOTFILES_ROOT/bin/wt" add feature-x
  TMUX= run "$DOTFILES_ROOT/bin/wt" ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-x"* ]]
}

@test "wt --help prints usage" {
  run "$DOTFILES_ROOT/bin/wt" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree orchestrator"* ]]
}

@test "wt claude without tmux creates worktree path (claude binary absent tolerated)" {
  cd "$HOME/lin_code/repoA"
  # Stub claude to avoid requiring the real binary.
  mkdir -p "$HOME/bin-stub"
  cat > "$HOME/bin-stub/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude stub: $*" >&2
exit 0
STUB
  chmod +x "$HOME/bin-stub/claude"
  PATH="$HOME/bin-stub:$PATH" TMUX= run "$DOTFILES_ROOT/bin/wt" claude feature-y
  [ -d "$HOME/lin_code/wt/repoA/feature-y" ]
}
