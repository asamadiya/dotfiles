# Observability Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the observability substrate described in [2026-04-19-observability-design.md](../specs/2026-04-19-observability-design.md) — host telemetry, shell awareness, session continuity, artifact durability, project/repo-state surfaces — on branch `power-tui` in `~/my_stuff/dotfiles`. Every commit local (no auto-push).

**Architecture:** Additive shell scripts in `bin/`, configs in `config/`, systemd `--user` units in `systemd/`, managed `>>> <<<` blocks inside existing tmux and Claude Code config templates. Every script degrades silently when tools/hardware are absent (ld4 ↔ ld5 portable; no-GPU safe). TDD where practical (`bats-core` for shell units, `shellcheck` for lint); manual smoke tests for tmux + systemd integration. One logically-independent commit per task.

**Tech Stack:** bash 5.x (scripts), zsh 5.9 (interactive — productivity phase installs; this phase degrades gracefully when zsh hooks are absent), tmux 3.5a, tmux-resurrect + tmux-continuum, `systemd --user`, `age` (passphrase mode), `git` + `git-lfs`, `bats-core` + `shellcheck` for test tooling.

---

## Prerequisites (once per host, before starting tasks)

- [ ] Install bootstrap tools:
  ```bash
  sudo tdnf install -y git-lfs shellcheck bats
  # age: if not available via tdnf on AzL3, install static binary:
  if ! command -v age >/dev/null; then
    mkdir -p "$HOME/.local/bin"
    curl -L https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz \
      | tar xz -C "$HOME/.local/bin/" --strip-components=1 age/age age/age-keygen
    chmod +x "$HOME/.local/bin/age" "$HOME/.local/bin/age-keygen"
  fi
  ```
- [ ] Create the age passphrase file (passphrase: `typewriter` — chosen during brainstorm):
  ```bash
  mkdir -p "$HOME/.config/age"
  printf 'typewriter\n' > "$HOME/.config/age/state-passphrase"
  chmod 600 "$HOME/.config/age/state-passphrase"
  ```
- [ ] Confirm `git --version` ≥ 2.30, `tmux -V` = 3.5a, `systemctl --user status` returns without error.
- [ ] Confirm starting state of `~/my_stuff/dotfiles`:
  ```bash
  cd ~/my_stuff/dotfiles
  git rev-parse --abbrev-ref HEAD   # → power-tui
  git status                        # → clean working tree
  git config user.email              # → asamadiya@users.noreply.github.com
  ```
- [ ] Verify `~/lin_code/` exists (work dir). If not, create an empty dir: `mkdir -p ~/lin_code`.

---

## Task 0 — Scaffold test infrastructure

Adds `bats-core` test skeleton and a `shellcheck` helper so every shell script landing in later tasks can be linted + unit-tested.

**Files:**
- Create: `tests/bats/helpers.bash`
- Create: `tests/bats/.gitkeep`
- Create: `bin/lint-shell.sh`
- Modify: `sync.sh` (append `lint-shell.sh` to `BIN_SCRIPTS`)

- [ ] **Step 1: Write `tests/bats/helpers.bash`**

```bash
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
```

- [ ] **Step 2: Write `bin/lint-shell.sh`**

```bash
#!/usr/bin/env bash
# Lint every shell script in bin/ and tests/ using shellcheck.
# Exits non-zero if any script fails.

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

while IFS= read -r f; do
  if ! shellcheck -x "$f"; then
    echo "shellcheck failed: $f" >&2
    failed=1
  fi
done < <(find "$ROOT/bin" "$ROOT/tests" -type f \( -name '*.sh' -o -name '*.bash' \) -not -path '*/\.*' 2>/dev/null)

exit "$failed"
```

- [ ] **Step 3: Make `lint-shell.sh` executable**

```bash
chmod +x bin/lint-shell.sh
touch tests/bats/.gitkeep
```

- [ ] **Step 4: Run the linter to prove baseline passes**

Run:
```bash
bin/lint-shell.sh
```
Expected: exit 0, no output (no scripts yet, or existing ones already lint-clean).

- [ ] **Step 5: Append to `BIN_SCRIPTS` in sync.sh**

Locate the `BIN_SCRIPTS=(...)` array in `sync.sh` and append `lint-shell.sh` as a new element.

- [ ] **Step 6: Commit**

```bash
git add tests/bats/helpers.bash tests/bats/.gitkeep bin/lint-shell.sh sync.sh
git commit -m "Scaffold bats test dir + bin/lint-shell.sh shellcheck wrapper"
```

---

## Task 1 — Two-identity git config

Enforces personal identity under `~/my_stuff/` and work identity under `~/lin_code/` via `includeIf`.

**Files:**
- Modify: `git/gitconfig`
- Create: `git/gitconfig-personal`
- Create: `git/gitconfig-work.example`
- Modify: `install.sh` (symlink the personal config; document work file)
- Modify: `.gitignore` at repo root (add `git/gitconfig-work` if present locally)

- [ ] **Step 1: Add `includeIf` blocks to `git/gitconfig`**

Append to the existing `git/gitconfig`:

```
[includeIf "gitdir:~/my_stuff/"]
    path = ~/.gitconfig-personal

[includeIf "gitdir:~/lin_code/"]
    path = ~/.gitconfig-work
```

- [ ] **Step 2: Create `git/gitconfig-personal`**

```
[user]
    name = asamadiya
    email = asamadiya@users.noreply.github.com
    signingkey =

[commit]
    gpgsign = false
```

- [ ] **Step 3: Create `git/gitconfig-work.example`**

```
# Copy to ~/.gitconfig-work on each work host and replace __WORK_EMAIL__ with the
# real LinkedIn email. This file is a template only; the real file is gitignored.

[user]
    name = __WORK_NAME__
    email = __WORK_EMAIL__

[commit]
    gpgsign = false
```

- [ ] **Step 4: Update `.gitignore`**

Append:
```
# Work-side git identity is local-only (real email never committed)
git/gitconfig-work
```

- [ ] **Step 5: Wire install.sh to symlink the personal config**

Find the block in `install.sh` that symlinks `git/gitconfig`. Add alongside it:

```bash
ln -sfn "$DOTFILES/git/gitconfig-personal" "$HOME/.gitconfig-personal"
```

And at the end of the gitconfig block, add a reminder:

```bash
if [ ! -f "$HOME/.gitconfig-work" ]; then
  echo "Note: copy $DOTFILES/git/gitconfig-work.example to ~/.gitconfig-work and fill in your work email."
fi
```

- [ ] **Step 6: Test identity resolution**

Run (without install.sh yet — simulate):
```bash
ln -sfn "$PWD/git/gitconfig-personal" "$HOME/.gitconfig-personal"
cd /tmp && mkdir -p test-identity && cd test-identity && git init
git config user.email   # expect nothing yet
cd ~/my_stuff/dotfiles && git config user.email   # expect asamadiya@users.noreply.github.com
```

- [ ] **Step 7: Commit**

```bash
git add git/gitconfig git/gitconfig-personal git/gitconfig-work.example install.sh .gitignore
git commit -m "Two-identity git config: includeIf for ~/my_stuff vs ~/lin_code"
```

---

## Task 2 — LFS template + apply helper

Provides the default `.gitattributes` pattern set + a helper script that drops it into any target repo.

**Files:**
- Create: `config/gitattributes-lfs-template`
- Create: `bin/lfs-template-apply`
- Modify: `sync.sh` (append `lfs-template-apply` to `BIN_SCRIPTS`)

- [ ] **Step 1: Create `config/gitattributes-lfs-template`**

```
*.age filter=lfs diff=lfs merge=lfs -text
*.db filter=lfs diff=lfs merge=lfs -text
*.sqlite filter=lfs diff=lfs merge=lfs -text
*.cast filter=lfs diff=lfs merge=lfs -text
*.gz filter=lfs diff=lfs merge=lfs -text
*.zst filter=lfs diff=lfs merge=lfs -text
*.tar filter=lfs diff=lfs merge=lfs -text
*.zip filter=lfs diff=lfs merge=lfs -text
*.pdf filter=lfs diff=lfs merge=lfs -text
*.png filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.jpeg filter=lfs diff=lfs merge=lfs -text
*.webp filter=lfs diff=lfs merge=lfs -text
*.mp4 filter=lfs diff=lfs merge=lfs -text
*.mov filter=lfs diff=lfs merge=lfs -text
*.wav filter=lfs diff=lfs merge=lfs -text
*.mp3 filter=lfs diff=lfs merge=lfs -text
*.pt filter=lfs diff=lfs merge=lfs -text
*.onnx filter=lfs diff=lfs merge=lfs -text
*.safetensors filter=lfs diff=lfs merge=lfs -text
*.parquet filter=lfs diff=lfs merge=lfs -text
*.bin filter=lfs diff=lfs merge=lfs -text
```

- [ ] **Step 2: Create `bin/lfs-template-apply`**

```bash
#!/usr/bin/env bash
# Copy the dotfiles LFS .gitattributes template into the target repo, merging with
# any existing rules (idempotent: appends only missing patterns).
#
# Usage: bin/lfs-template-apply <repo-path>
#
# Does NOT run `git lfs install` per spec §7.4 — commit-time detection handles that.

set -euo pipefail

repo="${1:-}"
[[ -n "$repo" ]] || { echo "usage: lfs-template-apply <repo-path>" >&2; exit 2; }
[[ -d "$repo/.git" ]] || { echo "not a git repo: $repo" >&2; exit 2; }

src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/gitattributes-lfs-template"
[[ -f "$src" ]] || { echo "template missing: $src" >&2; exit 2; }

dst="$repo/.gitattributes"
touch "$dst"

added=0
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  if ! grep -qxF "$line" "$dst"; then
    printf '%s\n' "$line" >> "$dst"
    added=$((added + 1))
  fi
done < "$src"

echo "lfs-template-apply: added $added new patterns to $dst"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x bin/lfs-template-apply
```

- [ ] **Step 4: Write bats test `tests/bats/lfs-template-apply.bats`**

```bash
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
```

- [ ] **Step 5: Run tests**

```bash
bats tests/bats/lfs-template-apply.bats
```
Expected: 4/4 pass.

- [ ] **Step 6: Run shellcheck**

```bash
bin/lint-shell.sh
```
Expected: exit 0.

- [ ] **Step 7: Append `lfs-template-apply` to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 8: Commit**

```bash
git add config/gitattributes-lfs-template bin/lfs-template-apply tests/bats/lfs-template-apply.bats sync.sh
git commit -m "Add .gitattributes LFS template + bin/lfs-template-apply idempotent helper"
```

---

## Task 3 — `bin/sysstat.sh` (tmux status segment)

Replaces `bin/host-health.sh` with a unified CPU/MEM/DISK/GPU/load segment.

**Files:**
- Create: `bin/sysstat.sh`
- Create: `tests/bats/sysstat.bats`

- [ ] **Step 1: Write `bin/sysstat.sh`**

```bash
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
mem_col=$(colorize "$((100 - mem_pct))" 25 10)   # free-side thresholds inverted
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/sysstat.sh
```

- [ ] **Step 3: Write `tests/bats/sysstat.bats`**

```bash
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
```

- [ ] **Step 4: Run tests + lint**

```bash
bats tests/bats/sysstat.bats
bin/lint-shell.sh
```
Expected: 4/4 pass; shellcheck clean.

- [ ] **Step 5: Commit**

```bash
git add bin/sysstat.sh tests/bats/sysstat.bats
git commit -m "Add bin/sysstat.sh unified tmux status segment with bats tests"
```

---

## Task 4 — NVIDIA daemon + systemd user unit

Background daemon that caches `nvidia-smi` output to `/tmp/nvidia-stats`. Silent when driver absent.

**Files:**
- Create: `bin/nvidia-daemon.sh`
- Create: `systemd/nvidia-daemon.service.tpl`
- Modify: `install.sh` (generate + enable the unit if `/proc/driver/nvidia` exists)

- [ ] **Step 1: Write `bin/nvidia-daemon.sh`**

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/nvidia-daemon.sh
```

- [ ] **Step 3: Write `systemd/nvidia-daemon.service.tpl`**

```ini
[Unit]
Description=NVIDIA GPU telemetry cache writer (for tmux sysstat segment)
After=default.target

[Service]
Type=simple
ExecStart=__HOME__/bin/nvidia-daemon.sh
Restart=on-failure
RestartSec=10
# Silent exit (no NVIDIA driver) is success; don't restart-loop on that.
SuccessExitStatus=0

[Install]
WantedBy=default.target
```

- [ ] **Step 4: Wire into install.sh**

Inside `install.sh` (next to the existing `tmux.service.tpl` generation):

```bash
# --- nvidia-daemon (only if driver detected) ---
if [ -d /proc/driver/nvidia ]; then
  sed -e "s|__HOME__|$HOME|g" -e "s|__USER__|$USER|g" \
    "$DOTFILES/systemd/nvidia-daemon.service.tpl" \
    > "$HOME/.config/systemd/user/nvidia-daemon.service"
  systemctl --user daemon-reload
  systemctl --user enable --now nvidia-daemon.service
  echo "nvidia-daemon.service enabled"
else
  echo "nvidia-daemon: NVIDIA driver absent, skipping service install"
fi
```

- [ ] **Step 5: Smoke-test the script manually**

On a no-GPU host (ld5 today): `bin/nvidia-daemon.sh` should print `nvidia-daemon: NVIDIA driver not present; exiting cleanly` and exit 0.

On a GPU host: start it in the background for 5 s, then check:
```bash
bin/nvidia-daemon.sh &
sleep 5
cat /tmp/nvidia-stats    # should show three integers
kill %1
```

- [ ] **Step 6: Run shellcheck**

```bash
bin/lint-shell.sh
```

- [ ] **Step 7: Append `nvidia-daemon.sh` to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 8: Commit**

```bash
git add bin/nvidia-daemon.sh systemd/nvidia-daemon.service.tpl install.sh sync.sh
git commit -m "Add nvidia-daemon.sh + systemd user unit for cached GPU telemetry"
```

---

## Task 5 — tmux config: sysstat block, 5s interval, set-clipboard on

Swap the existing `host-health` managed block for the new `sysstat` block; tighten refresh interval; add explicit clipboard propagation.

**Files:**
- Modify: `tmux/tmux.conf.local.tpl`

- [ ] **Step 1: Replace the host-health managed block**

Locate this block (around lines 190–194):

```
# >>> host-health segment (managed) >>>
set-option -ga status-right " #(__HOME__/bin/host-health.sh)"
# <<< host-health segment (managed) <<<
```

Replace with:

```
# >>> sysstat segment (managed) >>>
set-option -ga status-right " #(__HOME__/bin/sysstat.sh)"
# <<< sysstat segment (managed) <<<
```

- [ ] **Step 2: Add `status-interval 5` + `set-clipboard on`**

Add to the `-- user customizations --` section (after the existing `set -g mouse on` line):

```
# Tighter refresh for livelier CPU% + MEM signals
set -g status-interval 5

# Explicit OSC 52 propagation so yank-to-clipboard reaches Mac terminal
set -g set-clipboard on
```

- [ ] **Step 3: Run `install.sh` (simulated) to regenerate tmux.conf.local**

```bash
# Just verify the template resolves cleanly:
sed -e "s|__HOME__|$HOME|g" -e "s|__USER__|$USER|g" tmux/tmux.conf.local.tpl \
  > /tmp/tmux.conf.local.test
grep sysstat /tmp/tmux.conf.local.test
grep 'status-interval 5' /tmp/tmux.conf.local.test
grep 'set-clipboard on' /tmp/tmux.conf.local.test
rm /tmp/tmux.conf.local.test
```

- [ ] **Step 4: Live smoke test**

```bash
cp /tmp/tmux.conf.local.test ~/.tmux.conf.local 2>/dev/null || true
# Better: install.sh will handle this. For now, trigger:
tmux source ~/.tmux.conf 2>/dev/null || true
```

Confirm the status-right now shows CPU/MEM/DISK/(GPU)/L instead of the old host-health.

- [ ] **Step 5: Commit**

```bash
git add tmux/tmux.conf.local.tpl
git commit -m "tmux: swap host-health → sysstat segment, status-interval 5, set-clipboard on"
```

---

## Task 6 — Retire `bin/host-health.sh`

Remove the script + its references in `BIN_SCRIPTS`, `README.md`, `CLAUDE.md`.

**Files:**
- Delete: `bin/host-health.sh`
- Modify: `sync.sh` (remove from `BIN_SCRIPTS`)
- Modify: `README.md` (replace any mention)
- Modify: `CLAUDE.md` (Key Scripts table entry)

- [ ] **Step 1: Remove the script**

```bash
git rm bin/host-health.sh
```

- [ ] **Step 2: Remove from `BIN_SCRIPTS` in sync.sh**

Delete the `host-health.sh` entry.

- [ ] **Step 3: Update `README.md`**

Find any bin/ tree entry mentioning `host-health.sh` and replace with `sysstat.sh` (unified status segment with per-metric color escalation).

- [ ] **Step 4: Update `CLAUDE.md` Key Scripts table**

Replace the `bin/host-health.sh` row with:

```
| `bin/sysstat.sh` | Unified tmux status segment: CPU%/MEM/DISK/GPU/load with per-metric color escalation |
| `bin/nvidia-daemon.sh` | systemd --user service that caches nvidia-smi to /tmp/nvidia-stats (silent if no driver) |
```

- [ ] **Step 5: Commit**

```bash
git add bin/host-health.sh sync.sh README.md CLAUDE.md
git commit -m "Retire bin/host-health.sh (superseded by sysstat.sh)"
```

---

## Task 7 — `bin/tmux-save-copilot-sessions`

Post-save hook that walks `~/.copilot/session-state/*/inuse.*.lock` and rewrites saved tmux-resurrect command strings from `copilot` → `copilot --resume=<uuid> --allow-all-tools`.

**Files:**
- Create: `bin/tmux-save-copilot-sessions`
- Create: `tests/bats/tmux-save-copilot.bats`

- [ ] **Step 1: Write `bin/tmux-save-copilot-sessions`**

```bash
#!/usr/bin/env bash
# Post-save hook for tmux-resurrect: map panes running `copilot` to their
# Copilot CLI session UUIDs and rewrite the saved command line so restore
# resumes the exact session.
#
# Mirror of bin/tmux-save-claude-sessions (same repo).

set -eu

RESURRECT_DIR="$HOME/.tmux/resurrect"
LAST="$RESURRECT_DIR/last"
SESSION_STATE="$HOME/.copilot/session-state"

[[ -L "$LAST" && -f "$LAST" ]] || exit 0
[[ -d "$SESSION_STATE" ]] || exit 0

# Build PID → session-uuid map from inuse.*.lock files.
declare -A PID_TO_UUID
for lock in "$SESSION_STATE"/*/inuse.*.lock; do
  [[ -e "$lock" ]] || continue
  uuid=$(basename "$(dirname "$lock")")
  fname=$(basename "$lock")             # inuse.<pid>.lock
  pid=${fname#inuse.}; pid=${pid%.lock}
  [[ "$pid" =~ ^[0-9]+$ ]] || continue
  PID_TO_UUID[$pid]=$uuid
done

(( ${#PID_TO_UUID[@]} )) || exit 0

# tmux list-panes: pane_pid + pane_id.
declare -A PANE_TO_UUID
while IFS=' ' read -r pane_pid pane_id; do
  # Walk up /proc/<pid>/status PPid chain looking for a known copilot pid.
  pid=$pane_pid
  for _ in 1 2 3 4 5; do
    if [[ -n "${PID_TO_UUID[$pid]:-}" ]]; then
      PANE_TO_UUID[$pane_id]=${PID_TO_UUID[$pid]}
      break
    fi
    # Iterate through child pids of pane_pid too (shell children).
    for child in $(pgrep -P "$pid" 2>/dev/null); do
      if [[ -n "${PID_TO_UUID[$child]:-}" ]]; then
        PANE_TO_UUID[$pane_id]=${PID_TO_UUID[$child]}
        break 2
      fi
    done
    ppid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)
    [[ -z "$ppid" || "$ppid" == 0 ]] && break
    pid=$ppid
  done
done < <(tmux list-panes -a -F '#{pane_pid} #{pane_id}')

(( ${#PANE_TO_UUID[@]} )) || exit 0

# Write a backup map + rewrite the resurrect save file in-place.
MAP_FILE="$RESURRECT_DIR/copilot-sessions.txt"
: > "$MAP_FILE"
for pane in "${!PANE_TO_UUID[@]}"; do
  printf '%s %s\n' "$pane" "${PANE_TO_UUID[$pane]}" >> "$MAP_FILE"
done

TARGET=$(readlink -f "$LAST")
TMP="${TARGET}.tmp"

# Rewrite: for each pane line that has command == "copilot", splice the --resume flag.
# Resurrect pane line format (tab-separated):
#   pane\t<session>\t<win_idx>\t...\t<pane_id>\t...\t<command>\t...
awk -v OFS='\t' -v map_file="$MAP_FILE" '
  BEGIN {
    while ((getline line < map_file) > 0) {
      n = split(line, a, " ")
      if (n == 2) M[a[1]] = a[2]
    }
  }
  /^pane/ {
    # Find the pane_id field (last numeric column matching %N) and command field.
    # Easiest: scan for a "%N" token — resurrect keeps it.
    pane_id = ""
    for (i=1; i<=NF; i++) if ($i ~ /^%[0-9]+$/) pane_id = $i
    if (pane_id in M) {
      # The command is the last field; normalize to include --resume and --allow-all-tools.
      cmd = $NF
      if (cmd == "copilot" || cmd ~ /^copilot($| )/) {
        $NF = "copilot --resume=" M[pane_id] " --allow-all-tools"
      }
    }
    print; next
  }
  { print }
' "$TARGET" > "$TMP"

mv "$TMP" "$TARGET"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/tmux-save-copilot-sessions
```

- [ ] **Step 3: Write `tests/bats/tmux-save-copilot.bats`**

```bash
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
```

(Full integration test — rewriting resurrect files — is part of the manual smoke test below.)

- [ ] **Step 4: Run tests + lint**

```bash
bats tests/bats/tmux-save-copilot.bats
bin/lint-shell.sh
```

- [ ] **Step 5: Append to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 6: Commit**

```bash
git add bin/tmux-save-copilot-sessions tests/bats/tmux-save-copilot.bats sync.sh
git commit -m "Add bin/tmux-save-copilot-sessions (post-save map + resurrect rewrite)"
```

---

## Task 8 — `bin/tmux-copilot-restore`

Per-pane restore script triggered by `@resurrect-processes 'copilot->…'`.

**Files:**
- Create: `bin/tmux-copilot-restore`

- [ ] **Step 1: Write `bin/tmux-copilot-restore`**

```bash
#!/usr/bin/env bash
# Resurrect-inline restore strategy for GitHub Copilot CLI.
# Invoked by tmux-resurrect for every pane whose saved command starts with `copilot`.
# Cleans stale inuse locks, unsets env leaks, relaunches with YOLO flag.

set -eu

SAVED_CMD="${1:-copilot}"
SESSION_STATE="$HOME/.copilot/session-state"

# --- clean stale locks (>30s old) — a crashed VM leaves locks behind ---------
if [[ -d "$SESSION_STATE" ]]; then
  find "$SESSION_STATE" -maxdepth 2 -name 'inuse.*.lock' -mmin +0 -print0 2>/dev/null \
    | while IFS= read -r -d '' lock; do
      mtime=$(stat -c %Y "$lock")
      now=$(date +%s)
      if (( now - mtime > 30 )); then rm -f "$lock"; fi
    done
fi

# --- strip leaking env vars --------------------------------------------------
unset COPILOT_SESSION COPILOT_SESSION_ID COPILOT_RUNTIME COPILOT_API_KEY \
      GH_COPILOT_TOKEN GITHUB_COPILOT_TOKEN GH_COPILOT_INTEGRATION_ID

# --- ensure YOLO flag present (belt + suspenders with save-hook rewrite) ----
CMD="$SAVED_CMD"
[[ "$CMD" == *"--allow-all-tools"* ]] || CMD="$CMD --allow-all-tools"

exec bash -c "$CMD"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/tmux-copilot-restore
```

- [ ] **Step 3: Run shellcheck**

```bash
bin/lint-shell.sh
```

- [ ] **Step 4: Append to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 5: Commit**

```bash
git add bin/tmux-copilot-restore sync.sh
git commit -m "Add bin/tmux-copilot-restore (resurrect-inline restore for copilot)"
```

---

## Task 9 — Wire copilot into tmux-resurrect hook + process list

Update `tmux/tmux.conf.local.tpl` so the post-save hook chain runs both claude and copilot save-hooks, and so the restore strategy knows about `copilot`.

**Files:**
- Modify: `tmux/tmux.conf.local.tpl`

- [ ] **Step 1: Extend `@resurrect-hook-post-save-all`**

Locate:
```
set -g @resurrect-hook-post-save-all '__HOME__/bin/tmux-save-claude-sessions'
```

Replace with:
```
set -g @resurrect-hook-post-save-all '__HOME__/bin/tmux-save-claude-sessions; __HOME__/bin/tmux-save-copilot-sessions'
```

- [ ] **Step 2: Extend `@resurrect-processes`**

Locate:
```
set -g @resurrect-processes 'claude->__HOME__/bin/tmux-claude-restore ssh vim nvim htop man less tail top watch'
```

Replace with:
```
set -g @resurrect-processes 'claude->__HOME__/bin/tmux-claude-restore copilot->__HOME__/bin/tmux-copilot-restore ssh vim nvim htop man less tail top watch'
```

- [ ] **Step 3: Smoke test manually**

- Start a copilot session in a pane: `copilot -p "say hi" --allow-all-tools`.
- Trigger resurrect save: `prefix+C-s` (or wait 5 min for continuum).
- Kill tmux: `tmux kill-server`.
- Restart: `systemctl --user start tmux` (or `tmux new-session`).
- Continuum should auto-restore; the copilot pane should come back with the resumed session.

- [ ] **Step 4: Commit**

```bash
git add tmux/tmux.conf.local.tpl
git commit -m "tmux: wire copilot save-hook + restore-process into resurrect"
```

---

## Task 10 — `bin/wt` core (work-only enforcement; add/ls/jump/prune)

First cut of the worktree orchestrator. No agent or stack subcommands yet — those come in Tasks 11 and 12.

**Files:**
- Create: `bin/wt`
- Create: `tests/bats/wt-core.bats`

- [ ] **Step 1: Write `bin/wt` core**

```bash
#!/usr/bin/env bash
# wt — worktree orchestrator scoped to ~/lin_code/. See spec §6.3.
#
# Subcommands (this task):  add  ls  jump  prune
# Subcommands (task 11):    claude  copilot  (--record variants)
# Subcommands (task 12):    stack  submit  sl
#
# Layout: ~/lin_code/wt/<repo>/<branch>/
# Refuses to run unless cwd (or --repo arg) is inside ~/lin_code/.

set -euo pipefail

WT_ROOT="$HOME/lin_code/wt"
WORK_ROOT="$HOME/lin_code"

die()  { echo "wt: $*" >&2; exit 1; }
warn() { echo "wt: $*" >&2; }

# --- work-only enforcement ---------------------------------------------------
enforce_work_scope() {
  local repo_root=$1
  [[ "$(realpath "$repo_root")" == "$WORK_ROOT"/* ]] || \
    die "wt only operates under $WORK_ROOT (got: $repo_root)"
}

find_repo_root() {
  # Walk up to find .git dir.
  local dir=$PWD
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  die "not inside a git repo"
}

# --- subcommand: add ---------------------------------------------------------
sub_add() {
  local branch="${1:-}"
  [[ -n "$branch" ]] || die "usage: wt add <branch>"

  local repo_root repo_name
  repo_root=$(find_repo_root)
  enforce_work_scope "$repo_root"
  repo_name=$(basename "$repo_root")

  local dest="$WT_ROOT/$repo_name/$branch"
  mkdir -p "$(dirname "$dest")"

  if [[ -d "$dest" ]]; then
    warn "worktree already exists at $dest; reusing"
  else
    # Create branch if missing.
    if ! git -C "$repo_root" rev-parse --verify "$branch" >/dev/null 2>&1; then
      git -C "$repo_root" worktree add -b "$branch" "$dest"
    else
      git -C "$repo_root" worktree add "$dest" "$branch"
    fi
  fi

  # Open a tmux window named <repo>/<branch>, cd'd into dest.
  if [[ -n "${TMUX:-}" ]]; then
    tmux new-window -n "$repo_name/$branch" -c "$dest"
  fi

  echo "$dest"
}

# --- subcommand: ls ----------------------------------------------------------
sub_ls() {
  [[ -d "$WT_ROOT" ]] || return 0
  find "$WT_ROOT" -mindepth 2 -maxdepth 2 -type d | while read -r d; do
    local b; b=$(git -C "$d" branch --show-current 2>/dev/null || echo '?')
    local last; last=$(git -C "$d" log -1 --format='%h %s' 2>/dev/null || echo '?')
    local dirty; dirty=$(git -C "$d" status --porcelain 2>/dev/null | head -1)
    local flag='clean'; [[ -n "$dirty" ]] && flag='dirty'
    printf '%-50s %-20s %-6s %s\n' "$d" "$b" "$flag" "$last"
  done
}

# --- subcommand: jump --------------------------------------------------------
sub_jump() {
  command -v fzf >/dev/null || die "jump requires fzf (install via productivity phase)"
  local pick
  pick=$(sub_ls | fzf --header='pick worktree')
  [[ -n "$pick" ]] || exit 0
  local path; path=$(awk '{print $1}' <<< "$pick")
  local repo; repo=$(basename "$(dirname "$path")")
  local br;  br=$(basename "$path")
  if [[ -n "${TMUX:-}" ]]; then
    tmux select-window -t "$repo/$br" 2>/dev/null || tmux new-window -n "$repo/$br" -c "$path"
  else
    echo "cd $path"
  fi
}

# --- subcommand: prune -------------------------------------------------------
sub_prune() {
  [[ -d "$WT_ROOT" ]] || return 0
  find "$WT_ROOT" -mindepth 2 -maxdepth 2 -type d | while read -r d; do
    local br; br=$(git -C "$d" branch --show-current 2>/dev/null) || continue
    local repo_root; repo_root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || continue
    local main_ref; main_ref=$(git -C "$WORK_ROOT/$(basename "$(dirname "$d")")" symbolic-ref --short HEAD 2>/dev/null) || main_ref=master
    # If branch is merged into main, offer to prune.
    local main_wd="$WORK_ROOT/$(basename "$(dirname "$d")")"
    if git -C "$main_wd" merge-base --is-ancestor "$br" "$main_ref" 2>/dev/null; then
      read -r -p "remove merged worktree $d ($br → $main_ref)? [y/N] " ans
      if [[ "$ans" =~ ^[Yy]$ ]]; then
        git -C "$main_wd" worktree remove --force "$d"
      fi
    fi
  done
  # Also clean up admin metadata for deleted ones.
  for repo in "$WORK_ROOT"/*/; do
    [[ -d "$repo/.git" ]] && git -C "$repo" worktree prune 2>/dev/null || true
  done
}

# --- dispatch ----------------------------------------------------------------
cmd="${1:-}"; shift || true
case "$cmd" in
  add)    sub_add   "$@" ;;
  ls)     sub_ls    "$@" ;;
  jump)   sub_jump  "$@" ;;
  prune)  sub_prune "$@" ;;
  -h|--help|'') cat <<'EOF'
wt — worktree orchestrator for ~/lin_code/ (work-only)

Usage:
  wt add <branch>       create worktree at ~/lin_code/wt/<repo>/<branch>/
  wt ls                 list worktrees with branch/dirty/last-commit
  wt jump               fzf-pick a worktree, open in tmux window
  wt prune              remove merged worktrees (interactive)

Further subcommands (claude/copilot/stack/...) land in later tasks.
EOF
  ;;
  *) die "unknown subcommand: $cmd (try: wt --help)";;
esac
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/wt
```

- [ ] **Step 3: Write `tests/bats/wt-core.bats`**

```bash
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
```

- [ ] **Step 4: Run tests + lint**

```bash
bats tests/bats/wt-core.bats
bin/lint-shell.sh
```

- [ ] **Step 5: Append `wt` to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 6: Commit**

```bash
git add bin/wt tests/bats/wt-core.bats sync.sh
git commit -m "Add bin/wt core: add/ls/jump/prune under ~/lin_code/wt/ (work-only)"
```

---

## Task 11 — `bin/wt` agent subcommands (claude / copilot / --record)

Extend `bin/wt` with the AI-session-launch subcommands.

**Files:**
- Modify: `bin/wt` (append new subcommand handlers + dispatch entries)

- [ ] **Step 1: Append helpers at the bottom of `bin/wt` (before the dispatch block)**

Insert before `# --- dispatch ---`:

```bash
# --- agent subcommands -------------------------------------------------------
launch_agent() {
  # launch_agent <claude|copilot> <branch> [--record]
  local agent=$1 branch=$2; shift 2
  local record=0
  for a in "$@"; do [[ "$a" == "--record" ]] && record=1; done

  local dest; dest=$(sub_add "$branch")

  local cmd
  case "$agent" in
    claude)  cmd="claude --dangerously-skip-permissions" ;;
    copilot) cmd="copilot --allow-all-tools" ;;
    *) die "unknown agent: $agent" ;;
  esac

  if (( record )); then
    local cast="/tmp/wt-${agent}-$(date +%s).cast"
    cmd="asciinema rec --quiet $cast -c \"$cmd\""
    # TODO(user-guide): asciinema completion moves the cast into the state repo;
    # session-end-autocommit handles this via trap EXIT on the copilot launcher.
  fi

  if [[ -n "${TMUX:-}" ]]; then
    local repo; repo=$(basename "$(dirname "$dest")")
    tmux new-window -n "$repo/$branch" -c "$dest" "$cmd"
  else
    cd "$dest" && eval "$cmd"
  fi
}

sub_claude()  { launch_agent claude  "$@"; }
sub_copilot() { launch_agent copilot "$@"; }
```

- [ ] **Step 2: Add dispatch entries**

In the `case "$cmd" in` block, add:

```bash
  claude)  sub_claude  "$@" ;;
  copilot) sub_copilot "$@" ;;
```

Before the `-h|--help` arm, and update the `--help` text to:

```
  wt claude <branch> [--record]   add worktree + launch Claude YOLO
  wt copilot <branch> [--record]  add worktree + launch Copilot YOLO
```

- [ ] **Step 3: Write a smoke test**

Add to `tests/bats/wt-core.bats`:

```bash
@test "wt claude without tmux cds and would launch claude (dry-check)" {
  cd "$HOME/lin_code/repoA"
  TMUX= claude() { echo "claude called: $*"; }; export -f claude
  TMUX= run bash -c 'cd "$HOME/lin_code/repoA" && claude() { echo STUB; }; export -f claude; "$DOTFILES_ROOT/bin/wt" claude feature-y < /dev/null'
  # We are not expecting claude to actually exist on CI. Status may be nonzero but path exists.
  [ -d "$HOME/lin_code/wt/repoA/feature-y" ]
}
```

- [ ] **Step 4: Run tests + lint**

```bash
bats tests/bats/wt-core.bats
bin/lint-shell.sh
```

- [ ] **Step 5: Commit**

```bash
git add bin/wt tests/bats/wt-core.bats
git commit -m "Extend bin/wt with claude/copilot subcommands (+ YOLO flags, --record)"
```

---

## Task 12 — `bin/wt` stack/submit/sl subcommands

Adds stacked-PR support via `spr` + local stack view via `git-branchless`. Degrades gracefully if tools are absent.

**Files:**
- Modify: `bin/wt`

- [ ] **Step 1: Append new helpers**

Before `# --- dispatch ---`:

```bash
# --- stack subcommands (require spr and/or git-branchless) -------------------
sub_stack() {
  local base="${1:-master}"
  local repo_root; repo_root=$(find_repo_root); enforce_work_scope "$repo_root"
  local dest; dest=$(sub_add "$base-stack-$(date +%s)")
  (cd "$dest" && command -v spr >/dev/null && spr track || warn "spr not installed; skipping spr track")
}

sub_submit() {
  local repo_root; repo_root=$(find_repo_root); enforce_work_scope "$repo_root"
  if command -v spr >/dev/null; then
    spr diff "$@"
  else
    die "spr not installed — install in productivity phase"
  fi
}

sub_sl() {
  local repo_root; repo_root=$(find_repo_root); enforce_work_scope "$repo_root"
  if command -v git-branchless >/dev/null || git config --get branchless.core.mainBranch >/dev/null 2>&1; then
    git sl
  else
    warn "git-branchless not installed; falling back to git log --graph"
    git log --graph --oneline --all --decorate "$@"
  fi
}
```

- [ ] **Step 2: Add dispatch entries**

```bash
  stack)  sub_stack  "$@" ;;
  submit) sub_submit "$@" ;;
  sl)     sub_sl     "$@" ;;
```

And extend `--help`:

```
  wt stack <base>       add a stacked worktree, spr track (if installed)
  wt submit             spr diff → push stacked PRs (requires spr)
  wt sl                 git-branchless stacked log (fallback: git log --graph)
```

- [ ] **Step 3: Run lint**

```bash
bin/lint-shell.sh
```

- [ ] **Step 4: Commit**

```bash
git add bin/wt
git commit -m "Extend bin/wt with stack/submit/sl (spr + git-branchless, graceful fallback)"
```

---

## Task 13 — tmux keybindings for `wt`

Bind prefix+w/W/C-c/C-p to the `wt` subcommands via a managed block.

**Files:**
- Modify: `tmux/tmux.conf.local.tpl`

- [ ] **Step 1: Append a managed block**

At the end of the `-- user customizations --` section (or before the `# /!\ do not remove the following line` sentinel), add:

```
# >>> wt keybindings (managed) >>>
bind w   display-popup -E -w 80% -h 60% -d "#{pane_current_path}" "__HOME__/bin/wt jump"
bind W   command-prompt -p "wt add branch:"  "display-popup -E -d '#{pane_current_path}' '__HOME__/bin/wt add %%'"
bind C-c command-prompt -p "wt claude branch:"  "display-popup -E -d '#{pane_current_path}' '__HOME__/bin/wt claude %%'"
bind C-p command-prompt -p "wt copilot branch:" "display-popup -E -d '#{pane_current_path}' '__HOME__/bin/wt copilot %%'"
# <<< wt keybindings (managed) <<<
```

- [ ] **Step 2: Smoke test**

After install.sh regenerates `~/.tmux.conf.local`:

```bash
tmux source ~/.tmux.conf
# Press prefix+w → fzf picker (empty list ok)
# Press prefix+W, type "feature-x", Enter → new window named <repo>/feature-x
```

- [ ] **Step 3: Commit**

```bash
git add tmux/tmux.conf.local.tpl
git commit -m "tmux: add wt keybindings (prefix+w/W/C-c/C-p) as managed block"
```

---

## Task 14 — `bin/session-end-autocommit.sh`

The Claude/Copilot session-end auto-commit hook. Runs LFS detection + secret-pattern abort. No pre-commit. No push. No Co-Authored-By.

**Files:**
- Create: `bin/session-end-autocommit.sh`
- Create: `tests/bats/session-end-autocommit.bats`

- [ ] **Step 1: Write `bin/session-end-autocommit.sh`**

```bash
#!/usr/bin/env bash
# session-end-autocommit.sh <agent> <session-id>
#
# Called as a SessionEnd hook for Claude Code and from a trap EXIT wrapper for
# Copilot CLI. Commits the current working tree of the agent's cwd to the
# enclosing git repo. No push, no pre-commit, no Co-Authored-By.
#
# Behavior:
#   - Auto-adds binary files to Git LFS by extension (no `git lfs install` required).
#   - Aborts with a loud log if staged cleartext matches a known-secret regex.
#   - Exits 0 silently when: not in a repo / nothing to commit.

set -eu

AGENT="${1:-unknown}"
SID="${2:-unknown}"
SHORT="${SID:0:8}"

# --- locate repo root --------------------------------------------------------
if ! REPO=$(git rev-parse --show-toplevel 2>/dev/null); then
  exit 0  # not in a repo
fi

cd "$REPO"

# --- anything to commit? -----------------------------------------------------
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0  # clean
fi

# --- stage everything --------------------------------------------------------
git add -A

# --- LFS detection on staged binaries ---------------------------------------
if command -v git-lfs >/dev/null; then
  touch .gitattributes
  staged=$(git diff --cached --name-only --diff-filter=ACMR)
  declare -A SEEN=()
  for f in $staged; do
    [ -f "$f" ] || continue
    if file --mime-encoding -- "$f" 2>/dev/null | grep -qE ': (binary|octet-stream)$'; then
      ext="${f##*.}"
      [ -n "$ext" ] && [ "$ext" != "$f" ] || continue
      [ -n "${SEEN[$ext]:-}" ] && continue
      SEEN[$ext]=1
      pat="*.${ext}"
      grep -qxF "$pat filter=lfs diff=lfs merge=lfs -text" .gitattributes && continue
      git lfs track "$pat" >/dev/null
    fi
  done
  git add .gitattributes 2>/dev/null || true
  git add -u -- . 2>/dev/null || true
else
  echo "session-end-autocommit: git-lfs not installed; skipping LFS detection" >&2
fi

# --- secret-pattern abort ---------------------------------------------------
PATTERNS='(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})'
for f in $(git diff --cached --name-only --diff-filter=ACMR); do
  [ -f "$f" ] || continue
  # Skip files already LFS-tracked (binary blobs won't match regex anyway)
  if git check-attr filter -- "$f" 2>/dev/null | grep -q 'filter: lfs'; then continue; fi
  if grep -Eq "$PATTERNS" "$f" 2>/dev/null; then
    echo "session-end-autocommit: aborting — secret pattern in $f" >&2
    systemd-cat -t session-end-autocommit -p err <<< "aborted: secret pattern in $f" 2>/dev/null || true
    git reset >/dev/null 2>&1 || true
    exit 2
  fi
done

# --- commit ------------------------------------------------------------------
SUMMARY=$(git diff --cached --shortstat | sed 's/^ //')
MSG="session $AGENT $SHORT: ${SUMMARY:-working state snapshot}"
git commit -m "$MSG" --no-verify >/dev/null  # --no-verify only for THIS hook; manual commits still run pre-commit
exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/session-end-autocommit.sh
```

- [ ] **Step 3: Write `tests/bats/session-end-autocommit.bats`**

```bash
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
```

- [ ] **Step 4: Run tests + lint**

```bash
bats tests/bats/session-end-autocommit.bats
bin/lint-shell.sh
```

- [ ] **Step 5: Append `session-end-autocommit.sh` to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 6: Commit**

```bash
git add bin/session-end-autocommit.sh tests/bats/session-end-autocommit.bats sync.sh
git commit -m "Add bin/session-end-autocommit.sh (LFS + secret-abort, local-only)"
```

---

## Task 15 — Claude SessionEnd hook

Wire `session-end-autocommit.sh` into `claude/settings.json.tpl`.

**Files:**
- Modify: `claude/settings.json.tpl`

- [ ] **Step 1: Add the SessionEnd hook entry**

Open `claude/settings.json.tpl`. Locate the `"hooks"` object. Add (creating if missing) an entry:

```json
"SessionEnd": [
  {
    "matcher": "*",
    "hooks": [
      {
        "type": "command",
        "command": "__HOME__/bin/session-end-autocommit.sh claude ${CLAUDE_CODE_SESSION:-unknown}"
      }
    ]
  }
]
```

- [ ] **Step 2: Validate JSON after template substitution**

```bash
sed -e "s|__HOME__|$HOME|g" -e "s|__USER__|$USER|g" claude/settings.json.tpl > /tmp/claude-settings.json
jq . /tmp/claude-settings.json > /dev/null  # must parse
rm /tmp/claude-settings.json
```

- [ ] **Step 3: Commit**

```bash
git add claude/settings.json.tpl
git commit -m "Claude: wire SessionEnd hook to session-end-autocommit.sh"
```

---

## Task 16 — `bin/copilot` launcher wrapper (trap EXIT session-end)

Since Copilot CLI doesn't have a reliable hook surface, wrap every `copilot` launch in a bash function that runs the autocommit on exit.

**Files:**
- Create: `bin/copilot-with-autocommit`
- Modify: `bin/wt` (route `sub_copilot` through the wrapper)

- [ ] **Step 1: Write `bin/copilot-with-autocommit`**

```bash
#!/usr/bin/env bash
# Thin wrapper around `copilot` that runs session-end-autocommit on exit.
# wt copilot routes through this; direct `copilot` users can alias it
# to this wrapper in their shell rc.

set -eu

# Snapshot cwd so we autocommit in the dir the user launched from, not
# a subshell cd.
LAUNCH_DIR=$PWD

cleanup() {
  local ec=$?
  # best-effort session id from copilot session-state inuse lock of *our* pid
  local sid=unknown
  for lock in "$HOME/.copilot/session-state"/*/inuse.$$.lock; do
    [[ -e "$lock" ]] || continue
    sid=$(basename "$(dirname "$lock")")
    break
  done
  (cd "$LAUNCH_DIR" && "$HOME/bin/session-end-autocommit.sh" copilot "$sid") || true
  exit $ec
}
trap cleanup EXIT INT TERM

exec copilot "$@"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/copilot-with-autocommit
```

- [ ] **Step 3: Route `sub_copilot` in `bin/wt` through the wrapper**

In `bin/wt` `launch_agent()`, for the `copilot` case, change:
```
copilot) cmd="copilot --allow-all-tools" ;;
```
to:
```
copilot) cmd="$HOME/bin/copilot-with-autocommit --allow-all-tools" ;;
```

- [ ] **Step 4: Run lint**

```bash
bin/lint-shell.sh
```

- [ ] **Step 5: Append `copilot-with-autocommit` to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 6: Commit**

```bash
git add bin/copilot-with-autocommit bin/wt sync.sh
git commit -m "Add copilot-with-autocommit wrapper + route wt copilot through it"
```

---

## Task 17 — `bin/state-snapshot.sh`

Hourly state-repo snapshot (commit-only). Works with either of the two agent state repos (currently only work-side is enabled).

**Files:**
- Create: `bin/state-snapshot.sh`
- Create: `tests/bats/state-snapshot.bats`

- [ ] **Step 1: Write `bin/state-snapshot.sh`**

```bash
#!/usr/bin/env bash
# state-snapshot.sh — rsync session state + shell history + logs into the state
# repo, age-encrypt sensitive buckets, commit locally. Never push.
#
# Work-side state repo path (default): ~/lin_code/state
# Override via env: STATE_REPO=/some/path state-snapshot.sh

set -eu

STATE_REPO="${STATE_REPO:-$HOME/lin_code/state}"
AGE_PASS="$HOME/.config/age/state-passphrase"

[[ -d "$STATE_REPO/.git" ]] || { echo "state repo not initialised at $STATE_REPO" >&2; exit 0; }
[[ -f "$AGE_PASS" ]] || { echo "missing age passphrase at $AGE_PASS" >&2; exit 0; }

HOST=$(hostname -s)

# --- rsync sources -----------------------------------------------------------
mkdir -p "$STATE_REPO"/{claude/projects,copilot/session-state,atuin,tmux/resurrect,logs,recordings,snapshots/$HOST}

[[ -d "$HOME/.claude/projects" ]]      && rsync -a --delete "$HOME/.claude/projects/"      "$STATE_REPO/claude/projects/"
[[ -d "$HOME/.copilot/session-state" ]] && rsync -a --delete "$HOME/.copilot/session-state/" "$STATE_REPO/copilot/session-state/"
[[ -f "$HOME/.copilot/session-store.db" ]] && cp -f "$HOME/.copilot/session-store.db" "$STATE_REPO/copilot/session-store.db"
[[ -d "$HOME/.tmux/resurrect" ]]       && rsync -a --delete --exclude='last' "$HOME/.tmux/resurrect/" "$STATE_REPO/tmux/resurrect/"

# --- age-encrypt atuin history ----------------------------------------------
if command -v age >/dev/null && [[ -f "$HOME/.local/share/atuin/history.db" ]]; then
  age -p -o "$STATE_REPO/atuin/history.db.age" \
    < "$HOME/.local/share/atuin/history.db" < <(cat "$AGE_PASS") 2>/dev/null || \
    age -p -o "$STATE_REPO/atuin/history.db.age" --armor "$HOME/.local/share/atuin/history.db" \
      < "$AGE_PASS"  # age needs the passphrase on stdin
fi

# --- age-encrypt daily log rollup --------------------------------------------
TODAY=$(date +%Y-%m-%d)
LOG_DIR="$HOME/logs/tmux/$(date +%Y/%m/%d)"
if [[ -d "$LOG_DIR" ]]; then
  tar czf - -C "$LOG_DIR" . 2>/dev/null | age -p -o "$STATE_REPO/logs/${TODAY}.tar.gz.age" < "$AGE_PASS" || true
fi

# --- per-host inventory ------------------------------------------------------
{
  lscpu 2>/dev/null
  echo '---'
  lstopo --of txt 2>/dev/null
  echo '---'
  lsblk -f 2>/dev/null
  echo '---'
  lspci 2>/dev/null
  echo '---'
  cat /etc/os-release 2>/dev/null
  echo '---'
  uptime
  echo '---'
  df -h
} > "$STATE_REPO/snapshots/$HOST/inventory.txt" 2>/dev/null || true

# --- commit-time LFS + secret-pattern abort ---------------------------------
cd "$STATE_REPO"
git add -A

if command -v git-lfs >/dev/null; then
  touch .gitattributes
  staged=$(git diff --cached --name-only --diff-filter=ACMR)
  declare -A SEEN=()
  for f in $staged; do
    [ -f "$f" ] || continue
    if file --mime-encoding -- "$f" 2>/dev/null | grep -qE ': (binary|octet-stream)$'; then
      ext="${f##*.}"
      [ -n "$ext" ] && [ "$ext" != "$f" ] || continue
      [ -n "${SEEN[$ext]:-}" ] && continue
      SEEN[$ext]=1
      pat="*.${ext}"
      grep -qxF "$pat filter=lfs diff=lfs merge=lfs -text" .gitattributes && continue
      git lfs track "$pat" >/dev/null
    fi
  done
  git add .gitattributes 2>/dev/null || true
  git add -u -- . 2>/dev/null || true
fi

PATTERNS='(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})'
for f in $(git diff --cached --name-only --diff-filter=ACMR); do
  [ -f "$f" ] || continue
  if git check-attr filter -- "$f" 2>/dev/null | grep -q 'filter: lfs'; then continue; fi
  if grep -Eq "$PATTERNS" "$f" 2>/dev/null; then
    echo "state-snapshot: aborting — secret pattern in $f" >&2
    systemd-cat -t state-snapshot -p err <<< "aborted: secret pattern in $f" 2>/dev/null || true
    git reset >/dev/null 2>&1 || true
    exit 2
  fi
done

# --- commit (skip if nothing to commit) --------------------------------------
if git diff --cached --quiet; then
  exit 0
fi
SUMMARY=$(git diff --cached --shortstat | sed 's/^ //')
git commit -m "snapshot $HOST $(date +%Y-%m-%dT%H:%MZ): ${SUMMARY:-update}" --no-verify >/dev/null
exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/state-snapshot.sh
```

- [ ] **Step 3: Write `tests/bats/state-snapshot.bats`**

```bash
#!/usr/bin/env bats

load helpers

setup() {
  TMP=$(mktemp -d)
  mkdir -p "$TMP/state" "$TMP/.config/age" "$TMP/.claude/projects" "$TMP/.copilot/session-state"
  (cd "$TMP/state" && git init -q -b master && git config user.email t@t && git config user.name t)
  printf 'typewriter\n' > "$TMP/.config/age/state-passphrase"
  chmod 600 "$TMP/.config/age/state-passphrase"
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

@test "does not run git push" {
  # Smoke: ensure there's no 'origin' remote required.
  (cd "$STATE_REPO" && git remote | grep -q . && return 1 || return 0)
}
```

- [ ] **Step 4: Run tests + lint**

```bash
bats tests/bats/state-snapshot.bats
bin/lint-shell.sh
```

- [ ] **Step 5: Append `state-snapshot.sh` to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 6: Commit**

```bash
git add bin/state-snapshot.sh tests/bats/state-snapshot.bats sync.sh
git commit -m "Add bin/state-snapshot.sh (rsync + age + LFS + secret abort, commit-only)"
```

---

## Task 18 — systemd user timer for state-snapshot

Template service + timer, wired via install.sh.

**Files:**
- Create: `systemd/state-snapshot.service.tpl`
- Create: `systemd/state-snapshot.timer.tpl`
- Modify: `install.sh`

- [ ] **Step 1: Write the service template**

```ini
[Unit]
Description=Hourly state-repo snapshot (commit-only, no push)
After=default.target

[Service]
Type=oneshot
ExecStart=__HOME__/bin/state-snapshot.sh
Environment=HOME=__HOME__
```

Save as `systemd/state-snapshot.service.tpl`.

- [ ] **Step 2: Write the timer template**

```ini
[Unit]
Description=Hourly state-repo snapshot timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

Save as `systemd/state-snapshot.timer.tpl`.

- [ ] **Step 3: Wire into install.sh**

Adjacent to the nvidia-daemon block from Task 4:

```bash
# --- state-snapshot timer ---
for unit in state-snapshot.service state-snapshot.timer; do
  sed -e "s|__HOME__|$HOME|g" -e "s|__USER__|$USER|g" \
    "$DOTFILES/systemd/${unit}.tpl" \
    > "$HOME/.config/systemd/user/${unit}"
done
systemctl --user daemon-reload
systemctl --user enable --now state-snapshot.timer
```

- [ ] **Step 4: Smoke test**

```bash
# After install.sh runs:
systemctl --user list-timers | grep state-snapshot
systemctl --user start state-snapshot.service
journalctl --user -u state-snapshot.service | tail -20
```

- [ ] **Step 5: Commit**

```bash
git add systemd/state-snapshot.service.tpl systemd/state-snapshot.timer.tpl install.sh
git commit -m "Add state-snapshot systemd user timer (hourly, Persistent)"
```

---

## Task 19 — Pane-logging mode A (manual toggle)

`prefix+L` toggles `pipe-pane` logging on the focused pane.

**Files:**
- Create: `bin/pane-log-toggle.sh`
- Modify: `tmux/tmux.conf.local.tpl`

- [ ] **Step 1: Write `bin/pane-log-toggle.sh`**

```bash
#!/usr/bin/env bash
# pane-log-toggle.sh — flip tmux pipe-pane logging on/off for $TMUX_PANE.
# State tracked via a per-pane empty sentinel at /tmp/tmux-pane-log-active.<id>.

set -eu

pane="${TMUX_PANE:-}"
[[ -n "$pane" ]] || { echo "no TMUX_PANE"; exit 1; }

ID=${pane#%}
SENT="/tmp/tmux-pane-log-active.${ID}"
DAY=$(date +%Y/%m/%d)
LOG_DIR="$HOME/logs/tmux/$DAY"
mkdir -p "$LOG_DIR"

if [[ -f "$SENT" ]]; then
  tmux pipe-pane
  rm -f "$SENT"
  tmux display-message "pane logging: OFF ($pane)"
else
  LOG_FILE="$LOG_DIR/S-$(tmux display-message -p '#S')_W-$(tmux display-message -p '#I')_P-${ID}.log"
  tmux pipe-pane -o "cat >> $LOG_FILE"
  : > "$SENT"
  tmux display-message "pane logging: ON → $LOG_FILE"
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/pane-log-toggle.sh
```

- [ ] **Step 3: Append tmux managed block**

Add to `tmux/tmux.conf.local.tpl`:

```
# >>> pane-logging (managed) >>>
bind L run-shell "__HOME__/bin/pane-log-toggle.sh"
# <<< pane-logging (managed) <<<
```

- [ ] **Step 4: Smoke test**

```bash
# In a tmux pane:
# prefix+L   → "pane logging: ON → ~/logs/tmux/YYYY/MM/DD/S-*.log"
echo hello
# prefix+L   → "pane logging: OFF"
cat ~/logs/tmux/$(date +%Y/%m/%d)/*.log
```

- [ ] **Step 5: Append `pane-log-toggle.sh` to `BIN_SCRIPTS` in sync.sh.**

- [ ] **Step 6: Commit**

```bash
git add bin/pane-log-toggle.sh tmux/tmux.conf.local.tpl sync.sh
git commit -m "Add pane-logging mode A: prefix+L manual toggle"
```

---

## Task 20 — Pane-logging mode B (zsh-hook auto-on-shell, auto-off-TUI)

Opt-in global mode that re-enables logging on every shell prompt and disables it for known TUI commands via zsh `preexec`/`precmd` hooks. `prefix+M-L` toggles the mode.

**Files:**
- Create: `shell/zshrc.d/95-pane-log.zsh` (sourced iff zsh is present; harmless on bash-only hosts)
- Create: `bin/pane-log-mode.sh`
- Modify: `tmux/tmux.conf.local.tpl`
- Modify: `install.sh` (symlink zshrc.d if needed)

- [ ] **Step 1: Write `shell/zshrc.d/95-pane-log.zsh`**

```zsh
# Pane-logging mode B: auto-on for shell prompts, auto-off during known TUI commands.
# Toggled globally by /tmp/tmux-pane-log-mode-b sentinel.

_TUI_CMDS=(vim nvim htop btop lazygit less more watch top claude copilot man yazi broot)

_tui_check() {
  [[ -f /tmp/tmux-pane-log-mode-b ]] || return 1
  [[ -n ${TMUX_PANE:-} ]] || return 1
  local first=${1%% *}
  for c in ${_TUI_CMDS[@]}; do [[ $first == $c ]] && return 0; done
  return 1
}

_pane_log_on() {
  [[ -f /tmp/tmux-pane-log-mode-b ]] || return
  [[ -n ${TMUX_PANE:-} ]] || return
  local DAY=$(date +%Y/%m/%d)
  local LOG_DIR="$HOME/logs/tmux/$DAY"
  mkdir -p "$LOG_DIR"
  local LOG_FILE="$LOG_DIR/S-$(tmux display-message -p '#S')_W-$(tmux display-message -p '#I')_P-${TMUX_PANE#%}.log"
  tmux pipe-pane -o "cat >> $LOG_FILE"
}
_pane_log_off() { tmux pipe-pane 2>/dev/null || true; }

preexec() { if _tui_check "$1"; then _pane_log_off; fi }
precmd()  { _pane_log_on; }
```

- [ ] **Step 2: Write `bin/pane-log-mode.sh` (flip the global sentinel)**

```bash
#!/usr/bin/env bash
# pane-log-mode.sh — flip the /tmp/tmux-pane-log-mode-b sentinel.
set -eu
SENT=/tmp/tmux-pane-log-mode-b
if [[ -f "$SENT" ]]; then
  rm -f "$SENT"
  tmux display-message "pane-log mode B: OFF (globally)"
else
  : > "$SENT"
  tmux display-message "pane-log mode B: ON (shell panes auto-log; TUI panes auto-skip)"
fi
```

```bash
chmod +x bin/pane-log-mode.sh
```

- [ ] **Step 3: Extend the tmux managed block**

Replace the pane-logging managed block from Task 19 with:

```
# >>> pane-logging (managed) >>>
bind L   run-shell "__HOME__/bin/pane-log-toggle.sh"
bind M-L run-shell "__HOME__/bin/pane-log-mode.sh"
# <<< pane-logging (managed) <<<
```

- [ ] **Step 4: Wire `install.sh` to symlink the zshrc.d file**

Add under the shell wiring block:

```bash
mkdir -p "$HOME/.zshrc.d"
ln -sfn "$DOTFILES/shell/zshrc.d/95-pane-log.zsh" "$HOME/.zshrc.d/95-pane-log.zsh"
```

Note: if the user hasn't set up `~/.zshrc` to source `~/.zshrc.d/*.zsh` yet (productivity phase does this), the file is harmless.

- [ ] **Step 5: Commit**

```bash
git add shell/zshrc.d/95-pane-log.zsh bin/pane-log-mode.sh tmux/tmux.conf.local.tpl install.sh sync.sh
git commit -m "Add pane-logging mode B: zsh hooks + prefix+M-L toggle"
```

---

## Task 21 — logrotate for `~/logs/tmux/`

Keep the log pile bounded. Copied into `/etc/logrotate.d/` requires sudo; install.sh attempts, warns on failure.

**Files:**
- Create: `config/logrotate/tmux-logs`
- Modify: `install.sh`

- [ ] **Step 1: Write `config/logrotate/tmux-logs`**

```
/home/*/logs/tmux/*/*/*/*.log {
    daily
    rotate 30
    compress
    missingok
    notifempty
    copytruncate
}
```

- [ ] **Step 2: Wire install.sh**

```bash
if [ -w /etc/logrotate.d ] || sudo -n true 2>/dev/null; then
  sudo cp "$DOTFILES/config/logrotate/tmux-logs" /etc/logrotate.d/tmux-logs || \
    echo "install.sh: logrotate copy failed; copy manually: sudo cp $DOTFILES/config/logrotate/tmux-logs /etc/logrotate.d/tmux-logs"
else
  echo "install.sh: no sudo; copy $DOTFILES/config/logrotate/tmux-logs into /etc/logrotate.d/ manually when convenient"
fi
```

- [ ] **Step 3: Commit**

```bash
git add config/logrotate/tmux-logs install.sh
git commit -m "Add logrotate.d/tmux-logs + guarded install"
```

---

## Task 22 — Extend `bin/claude-statusline.sh` with dirty glyph

Add a `*` next to the branch when `git status --porcelain` is non-empty.

**Files:**
- Modify: `bin/claude-statusline.sh`

- [ ] **Step 1: Read the existing script and locate the BRANCH block.** (Lines ~17–20 per earlier Read.)

- [ ] **Step 2: Extend the branch rendering**

Find:
```bash
BRANCH=""
if [ -d "$DIR/.git" ] || git -C "$DIR" rev-parse --git-dir &>/dev/null; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
fi
```

Replace with:
```bash
BRANCH=""
DIRTY=""
if [ -d "$DIR/.git" ] || git -C "$DIR" rev-parse --git-dir &>/dev/null; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
    if [ -n "$(git -C "$DIR" status --porcelain 2>/dev/null | head -1)" ]; then
        DIRTY="*"
    fi
fi
```

Then find the line that outputs branch:
```bash
[ -n "$BRANCH" ] && OUT="${OUT} \033[36m${BRANCH}\033[0m"
```

Replace with:
```bash
[ -n "$BRANCH" ] && OUT="${OUT} \033[36m${BRANCH}${DIRTY}\033[0m"
```

- [ ] **Step 3: Smoke test**

```bash
echo '{"workspace":{"current_dir":"'$PWD'"},"model":{"display_name":"X"}}' | bin/claude-statusline.sh | cat -v
# Look for "master*" if tree is dirty, "master" if clean.
```

- [ ] **Step 4: Run shellcheck**

```bash
bin/lint-shell.sh
```

- [ ] **Step 5: Commit**

```bash
git add bin/claude-statusline.sh
git commit -m "claude-statusline: add dirty glyph next to branch"
```

---

## Task 23 — Copilot statusline — verify and commit settings baseline

The `copilot-status-beautifier` already has `--show git` / default-on project+git. Commit a settings JSON so the config is reproducible.

**Files:**
- Create: `config/copilot/statusline-settings.json`
- Modify: `install.sh` (symlink)

- [ ] **Step 1: Write `config/copilot/statusline-settings.json`**

```json
{
  "color": true,
  "useUnicode": true,
  "maxWidth": 140,
  "display": {
    "showModel": false,
    "showPromptLabel": false,
    "showProject": true,
    "showGit": true,
    "showUsage": true,
    "showTiming": true,
    "showTools": false,
    "showAgents": true,
    "maxTools": 2,
    "maxAgents": 2
  }
}
```

- [ ] **Step 2: Wire install.sh**

```bash
mkdir -p "$HOME/.copilot"
ln -sfn "$DOTFILES/config/copilot/statusline-settings.json" "$HOME/.copilot/statusline-settings.json"
```

- [ ] **Step 3: Commit**

```bash
git add config/copilot/statusline-settings.json install.sh
git commit -m "Commit copilot statusline settings (project+git on by default)"
```

---

## Task 24 — README.md — observability section

Add a dedicated section listing the new surfaces + commands so new-machine users can discover them.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add an "Observability" top-level section** after the existing tool-inventory block:

```markdown
## Observability

### Status surfaces
- **tmux status-right** — system metrics only (CPU%/MEM/DISK/GPU/load) via `bin/sysstat.sh`, refreshed every 5s.
- **Starship prompt** — cwd, git state (branch, dirty, ahead/behind), exit code, duration.
- **claude-statusline** — model, context %, cost, GPU, load, branch + dirty glyph.
- **copilot statusline** — model, context %, req count, tokens, duration, project + branch/dirty.

### Key scripts
- `bin/sysstat.sh` — unified tmux status segment.
- `bin/nvidia-daemon.sh` — background GPU telemetry writer (systemd `--user`).
- `bin/wt` — worktree orchestrator for `~/lin_code/` (add/ls/jump/prune/claude/copilot/stack/submit/sl).
- `bin/tmux-save-copilot-sessions` + `bin/tmux-copilot-restore` — Copilot session resurrect pair.
- `bin/session-end-autocommit.sh` — Claude/Copilot session-end auto-commit (local only, no push).
- `bin/state-snapshot.sh` — hourly systemd-timed state-repo snapshot.
- `bin/pane-log-toggle.sh` + `bin/pane-log-mode.sh` — per-pane and global tmux logging modes.

### Key bindings
- `prefix+w` — fzf over worktrees, jump in tmux.
- `prefix+W` — prompt for branch, create worktree + tmux window.
- `prefix+C-c` — prompt + `wt claude` (Claude with YOLO).
- `prefix+C-p` — prompt + `wt copilot` (Copilot with YOLO).
- `prefix+L` — toggle pane logging (mode A, per-pane).
- `prefix+M-L` — toggle pane-logging mode B (auto-on shell, auto-off TUI).

For the full design + rationale see `docs/superpowers/specs/2026-04-19-observability-design.md`.
The user guide for daily workflows: `docs/guides/2026-04-19-observability-user-guide.md`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "README: add Observability section summarising new surfaces + bindings"
```

---

## Task 25 — CLAUDE.md — Key Scripts update

The root-level dotfiles `CLAUDE.md` has a Key Scripts table. Update it to reflect every new script.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Edit the Key Scripts table**

Ensure entries for (adding missing rows):

```
| `bin/sysstat.sh` | Unified tmux status segment: CPU%/MEM/DISK/GPU/load with per-metric color escalation |
| `bin/nvidia-daemon.sh` | systemd --user service caching nvidia-smi output to /tmp/nvidia-stats |
| `bin/tmux-save-copilot-sessions` | post-save hook — maps tmux panes to Copilot CLI session IDs |
| `bin/tmux-copilot-restore` | Resurrect-inline restore for Copilot CLI panes (unsets env leaks, cleans stale locks) |
| `bin/wt` | Worktree orchestrator for ~/lin_code/ (add/ls/jump/prune/claude/copilot/stack/submit/sl) |
| `bin/session-end-autocommit.sh` | Claude/Copilot session-end auto-commit hook; LFS detection; secret-pattern abort; no push |
| `bin/copilot-with-autocommit` | Thin `copilot` wrapper that runs the session-end autocommit on exit |
| `bin/state-snapshot.sh` | Hourly state-repo snapshot (rsync + age + LFS, commit-only) |
| `bin/pane-log-toggle.sh` / `bin/pane-log-mode.sh` | Per-pane and global tmux pane-logging control |
| `bin/lfs-template-apply` | Copy the LFS .gitattributes template into a target repo (idempotent) |
| `bin/lint-shell.sh` | shellcheck wrapper over bin/ + tests/ |
```

Remove the host-health.sh row.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "CLAUDE.md: refresh Key Scripts table for observability phase"
```

---

## Task 26 — `env.txt` — rewrite from real state

Existing `env.txt` is stale (claims Mariner 2 / kernel 5.15 / tools not installed). Rewrite.

**Files:**
- Modify: `env.txt`

- [ ] **Step 1: Regenerate from live VM**

```bash
{
  echo "# env.txt — inventory snapshot"
  echo "# Generated: $(date -u +%Y-%m-%dT%H:%MZ) on $(hostname -s)"
  echo
  echo "## OS"
  cat /etc/os-release
  echo
  echo "## Kernel"
  uname -a
  echo
  echo "## Key tools (command -v probes)"
  for t in tmux bash zsh git git-lfs age jq shellcheck bats gh \
           htop btop lazygit delta difftastic starship atuin zoxide bat eza \
           fd ripgrep hyperfine just tldr scc onefetch spr git-branchless; do
    path=$(command -v "$t" || true)
    printf '  %-20s %s\n' "$t" "${path:-(missing)}"
  done
  echo
  echo "## tdnf top-level installed (excerpt)"
  tdnf -C list installed 2>/dev/null | awk 'NR>1{print $1}' | sort -u | head -40
} > env.txt
```

Review the result manually for anything to redact.

- [ ] **Step 2: Commit**

```bash
git add env.txt
git commit -m "env.txt: regenerate from real AzL3 / kernel 6.6 state"
```

---

## Task 27 — CHANGELOG.md entry for the phase

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Prepend an entry**

```
## 2026-04-19 — Observability phase (branch: power-tui)

New scripts:
- `bin/sysstat.sh` — unified tmux status segment
- `bin/nvidia-daemon.sh` — GPU telemetry daemon
- `bin/tmux-save-copilot-sessions`, `bin/tmux-copilot-restore`
- `bin/wt` — worktree orchestrator (work-only)
- `bin/session-end-autocommit.sh` + `bin/copilot-with-autocommit`
- `bin/state-snapshot.sh`
- `bin/pane-log-toggle.sh`, `bin/pane-log-mode.sh`
- `bin/lfs-template-apply`, `bin/lint-shell.sh`

New systemd units: `nvidia-daemon`, `state-snapshot.timer`.

New configs: `config/gitattributes-lfs-template`, `config/logrotate/tmux-logs`,
`config/copilot/statusline-settings.json`, `git/gitconfig-personal`,
`git/gitconfig-work.example`.

tmux config changes: sysstat segment replaces host-health; `status-interval 5`;
`set-clipboard on`; copilot resurrect-processes entry; wt and pane-logging
keybindings.

Claude config: `SessionEnd` hook → `session-end-autocommit.sh`.

Retired: `bin/host-health.sh`.

Per-repo `git lfs install` is NOT required — session-end and state-snapshot
hooks detect binaries and run `git lfs track` on demand. Install `git-lfs`
binary once per host (tdnf).

All auto-commits are LOCAL (no push) — user pushes manually when ready.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "CHANGELOG: observability phase entry"
```

---

## Task 28 — User guide (FINALE)

Write the end-user guide per spec §9.2b + acceptance criterion #21.

**Files:**
- Create: `docs/guides/2026-04-19-observability-user-guide.md`

- [ ] **Step 1: Write `docs/guides/2026-04-19-observability-user-guide.md`**

```markdown
# Observability — User Guide

This guide covers the observability surfaces and workflows added by the
`power-tui` branch. For the design rationale, see
[the observability spec](../superpowers/specs/2026-04-19-observability-design.md).

## Keybindings cheatsheet

### tmux (prefix: Ctrl-Space)

| Key | Action |
|---|---|
| `prefix+w` | Fuzzy-jump to any existing worktree under `~/lin_code/wt/` |
| `prefix+W` | Prompt for branch, create new worktree + tmux window |
| `prefix+C-c` | Prompt for branch, create worktree + launch Claude Code (YOLO) |
| `prefix+C-p` | Prompt for branch, create worktree + launch Copilot CLI (YOLO) |
| `prefix+L` | Toggle pane logging (mode A — per-pane, on-demand) |
| `prefix+M-L` | Toggle pane-log mode B globally (auto-on-shell, auto-off-TUI) |
| `prefix+g` | (after productivity phase installs lazygit) open lazygit in a popup |
| `prefix+d` | (after productivity phase) open `gh-dash` PR/issue dashboard |
| `prefix+f` | fuzzy pick session/window/pane (tmux-fzf) |
| `prefix+F` | tmux-fingers pattern-hint (URLs, hashes, paths) |
| `prefix+[` | Enter copy-mode (vi bindings) |

Mouse (unchanged from prior config): click-to-focus-pane, drag-border-to-resize,
wheel-to-scrollback, drag-to-select-and-copy (auto via xclip + OSC 52),
Shift+drag = native terminal select bypass.

### zsh (after productivity phase)

| Key | Action |
|---|---|
| `Ctrl-R` | atuin interactive history search (filter by cwd/exit/host) |
| `Up arrow` | linear per-session history (atuin Up-rewire disabled by design) |

### Aliases (once productivity phase lands)

```
lg  = lazygit
gst = git status
glg = git log --graph --oneline --all --decorate
gfix = git absorb --and-rebase
clx = scc .
rec = asciinema rec
```

## Daily workflows

### Start parallel work on three features simultaneously

1. `cd ~/lin_code/<repo>`
2. `prefix+C-c`, branch `feature-one` → tmux window `<repo>/feature-one` with Claude running YOLO.
3. `prefix+C-c`, branch `feature-two` → another window with Claude YOLO.
4. `prefix+C-p`, branch `feature-three` → Copilot YOLO window.
5. Switch between windows with `prefix+<N>` or `prefix+w` (fzf).
6. Each worktree is at `~/lin_code/wt/<repo>/feature-N/`. Changes in one do not affect the others.

### End a session

Just type `/exit` in Claude or `exit` in Copilot. The session-end hook fires:
- Runs in your worktree.
- Detects binary files; auto-`git lfs track`s their extensions.
- Aborts if it finds a recognised secret pattern (you'll see a loud log entry).
- Otherwise: `git add -A && git commit -m "session <agent> <short-id>: +X -Y"`.
- Does NOT push. You push manually when you're ready.

### Recover after a crash / reboot

1. VM comes back. `systemd --user tmux.service` auto-starts tmux.
2. tmux-continuum auto-restores your last session.
3. Each resurrected claude pane runs `claude --resume=<id> --dangerously-skip-permissions`.
4. Each resurrected copilot pane runs `copilot --resume=<id> --allow-all-tools`.
5. Windows keep their `<repo>/<branch>` names so you know which worktree is which.
6. If something is wrong: `tmux kill-server && systemctl --user restart tmux`.

### Search across past pane output

Pane logs land under `~/logs/tmux/YYYY/MM/DD/`.

```bash
rg 'OOM' ~/logs/tmux/
rg --files-with-matches 'curl.*/api/v2' ~/logs/tmux/2026/04/
```

Only panes where you turned logging on (`prefix+L`) or panes running under mode B
with a shell (not a TUI) will have log files.

### Browse your own shell history across hosts

`Ctrl-R` → atuin. Filter by:
- `Tab` → toggle filter mode (session / cwd / host / global)
- Type any substring; matches highlighted
- `Enter` executes, `Tab` places on prompt for editing

### State repo — what's in it, how to inspect

```bash
cd ~/lin_code/state
git log --oneline | head
ls claude/projects/          # Claude sessions
ls copilot/session-state/    # Copilot sessions
ls recordings/               # asciinema .cast files (if wt --record)
ls snapshots/<hostname>/     # host inventory
```

Decrypt the atuin history export:

```bash
age -d -o /tmp/history.db atuin/history.db.age
# Passphrase: the one in ~/.config/age/state-passphrase
sqlite3 /tmp/history.db 'SELECT command FROM history ORDER BY timestamp DESC LIMIT 20;'
```

Decrypt a log rollup:

```bash
age -d logs/2026-04-19.tar.gz.age | tar tz
```

## Commands reference

### `wt`

```
wt add <branch>            Create a worktree at ~/lin_code/wt/<repo>/<branch>/ + tmux window
wt ls                      List all worktrees with branch, dirty flag, last commit
wt jump                    fzf-pick a worktree, select that tmux window
wt prune                   Remove worktrees whose branches are merged (interactive)
wt claude <branch> [--record]    Add worktree + launch Claude YOLO (optionally record to asciinema)
wt copilot <branch> [--record]   Add worktree + launch Copilot YOLO
wt stack <base-branch>     Add a stacked worktree, spr track
wt submit                  spr diff → push stacked PRs (requires spr installed)
wt sl                      git-branchless stacked log (fallback: git log --graph)
```

`wt` refuses to run unless cwd is under `~/lin_code/`. Use plain git on `~/my_stuff/`.

### `sysstat.sh`

Runs as a tmux `#(...)` segment. Manually: `bin/sysstat.sh` prints a single
colored line. GPU segment only appears when `/tmp/nvidia-stats` is fresh
(< 30 s old), which is written by `nvidia-daemon.service`.

### `state-snapshot.sh`

Hourly systemd timer (`systemctl --user list-timers`). Runs manually:
`bin/state-snapshot.sh`. Commits to `~/lin_code/state/` only; never pushes.

Environment overrides:
- `STATE_REPO=/other/path bin/state-snapshot.sh` — snapshot to an alternate repo.

### `session-end-autocommit.sh`

Called automatically when Claude/Copilot exits. Manual use:
`bin/session-end-autocommit.sh claude <session-id>`. No push. No pre-commit.

### `pane-log-toggle.sh` / `pane-log-mode.sh`

Bound to `prefix+L` and `prefix+M-L`. Manual: `bin/pane-log-toggle.sh` from
inside a tmux pane.

## Troubleshooting

### "pane-border-status keeps overlapping my content"

It shouldn't — the observability design explicitly has pane-border-status **off**.
If you see it, check `tmux show -g pane-border-status`; run
`tmux set -g pane-border-status off` and restart.

### "sysstat segment shows CPU 0% forever"

Delete the state file — first-run sample is primed only after the second call:
```bash
rm /tmp/sysstat.cpu.state
```
Wait one `status-interval` (5 s). Back to normal.

### "Copilot resurrect re-launches but says 'session active elsewhere'"

The stale-lock cleanup didn't fire. Manually:
```bash
rm -f ~/.copilot/session-state/*/inuse.*.lock
tmux send-keys -t <pane> C-c 'copilot --resume=<uuid> --allow-all-tools' Enter
```

### "Auto-commit aborted with secret-pattern error"

A file in your worktree has a regex-matching string (likely a real token). The
commit was aborted and your working tree is intact. Inspect:
```bash
grep -rE '(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA)' .
```
Remove or redact, then commit manually (or let the next session-end fire).

### "state-snapshot.timer shows inactive"

```bash
systemctl --user status state-snapshot.timer
systemctl --user start state-snapshot.timer
journalctl --user -u state-snapshot.service
```
Most likely cause: missing `~/.config/age/state-passphrase` (the script exits 0
when the passphrase file is missing to avoid crashing the timer).

### "I want to push the state repo manually"

```bash
cd ~/lin_code/state
git log                       # review what will go out
git push origin master         # uses gh auth (work context)
```

### "I want to disable auto-commit entirely for a session"

Prefix the command: `NO_AUTOCOMMIT=1 claude ...`. The hook checks for
`NO_AUTOCOMMIT` at the top and exits 0 if set. (Note: this env-var hook
is a TODO for Task 14 — document in spec §12 as a follow-up.)

## Before-you-push checklist

Because auto-commit is always LOCAL, you control what leaves the machine.
Before `git push` on any work repo:

1. `git log origin/<branch>..HEAD` — inspect the commit sequence.
2. `git diff origin/<branch>..HEAD` — review the diff.
3. `grep -rE '(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA|password|secret)' <changed files>`
   — quick self-audit even though auto-commit already screens.
4. `git log --author=asamadiya` — confirm identity isn't mixed.

## Disaster recovery

### State repo encrypted files — "I forgot the passphrase"

The passphrase is stored at `~/.config/age/state-passphrase` on each host.
If all hosts and the file are lost simultaneously, the encrypted archives are
unrecoverable by design — they were bytes-locked.

### Worktree lost after a `git worktree remove --force`

Check the main repo's reflog:
```bash
cd ~/lin_code/<repo>
git reflog <branch>
git checkout -b <branch>-rescue <sha>
```
Worktree files are gone but commit history on the branch is intact.

### Auto-committed the wrong thing (rollback)

Since nothing is pushed:
```bash
git log -1             # see the hook's commit
git reset --soft HEAD~1  # un-commit, keep working tree
# edit as you like
git commit ...           # or just leave uncommitted until next hook
```
```

- [ ] **Step 2: Read the generated guide end-to-end**

```bash
less docs/guides/2026-04-19-observability-user-guide.md
```

Verify: every new script, every new keybinding, every new workflow appears. Every troubleshooting item references real state paths.

- [ ] **Step 3: Commit**

```bash
git add docs/guides/2026-04-19-observability-user-guide.md
git commit -m "docs: write observability user guide (final deliverable)"
```

---

## Post-implementation verification

Run through the spec's acceptance criteria (§10, items 1–21). Each criterion
should pass on ld5. Anything failing: open a follow-up task on `power-tui`.

After all 21 criteria pass, the phase is ready to merge:

```bash
git checkout master
git merge --no-ff power-tui -m "Merge observability phase (power-tui)"
# Do NOT push. User pushes manually.
```

---

## Self-review notes (author)

Spec coverage cross-check:

- §4 Host telemetry → Tasks 3, 4, 5, 6
- §5 Shell awareness → Tasks 19, 20, 21 (+ 18 state-snapshot handles atuin export)
- §6 Session continuity → Tasks 7, 8, 9, 10, 11, 12, 13
- §7 Artifact durability → Tasks 14, 15, 16, 17, 18, 2 (LFS)
- §8 Project/repo-state → Tasks 1 (identity), 22, 23 (statuslines); lazygit/delta/difftastic/spr/git-branchless/git-absorb/pre-commit/onefetch/scc/git-who installs are in the **productivity phase** (deferred per spec §13). Their wiring in `bin/wt` (stack/submit/sl) uses graceful fallback when binaries are absent.
- §9 File inventory → Tasks 3–23 cover every listed artifact.
- §10 Acceptance criteria → explicit verify step at end.
- §11 Rollback → implicit in per-task commits (git revert) + Task 18 systemd disable.
- §13 Out-of-scope — confirmed no productivity-layer work sneaking in.
