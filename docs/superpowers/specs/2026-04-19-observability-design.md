# Observability Design — dotfiles power-tui phase

Date: 2026-04-19
Scope: Observability phase only. Productivity phase (shell refactor, tool installs for daily CLI replacements, neovim, Mac-side dotfiles, NVIDIA driver) is deferred to a follow-up spec.

Final deliverable of the implementation plan: a user guide at `docs/guides/2026-04-19-observability-user-guide.md` that covers every new keybinding, command, and workflow produced by this phase. See §9.2b and acceptance criterion #21.

---

## 1. Motivation

User is a senior staff engineer, keyboard-first, vim/tmux native. Lives in tmux over SSH from Mac to Linux dev VMs (primary `spopuri-ld4`, secondary `spopuri-ld5` — Azure Linux 3, AMD EPYC 7V12, 108 GiB / zero swap, Tesla T4 with driver currently unloaded).

Thrives on observability. Wants "1000-eyes visibility" into the machine, his own workflow, and every active AI agent session. Every piece of work must live in a git repo so history is always tracked; binaries via Git LFS.

This phase builds the observability substrate — telemetry, shell awareness, session continuity, artifact durability, project/repo-state — before the productivity layer lands.

## 2. Principles

1. **Git-first.** Every artifact worth keeping auto-commits to a repo. Binaries via commit-time LFS detection.
2. **Two identities, never cross-wired.** `~/my_stuff/` = personal (asamadiya, PAT-only, no gh CLI). `~/lin_code/` = work (LinkedIn, gh CLI). `includeIf` git config enforces per-dir identity.
3. **Snappy over feature-rich.** Every added surface must have a measured cost budget. Turbo-load async where possible.
4. **YOLO-safe.** Claude/Copilot sessions always launch with permissions bypassed; the auto-commit hook captures all changes as revertible commits.
5. **No auto-push.** Every auto-commit stays local. User decides when to push, to prevent half-baked work ending up on PR-linked branches.
6. **Zero-config-failure.** Every script degrades silently when hardware/tool is absent (no-GPU hosts, no-atuin hosts, no-state-repo hosts). Portable across ld4 and ld5 by construction.
7. **No Co-Authored-By trailers, ever** — manual or automated commits.

## 3. Architecture overview

Five subtracks under observability:

| # | Subtrack | What it answers |
|---|---|---|
| 1 | Host telemetry | What is the machine doing *right now*? |
| 2 | Shell awareness | What did I just run, copy, see? |
| 3 | Session continuity | Where was I, in every tool, before the crash? |
| 4 | Artifact durability | Where is the record of the work? |
| 5 | Project/repo-state visibility | Which repo, which branch, which stack, which PR? |

Each subtrack has its own surfaces. Cross-cutting concerns (git state, clipboard, mouse) are placed in exactly one surface each to avoid duplication.

### 3.1 Surface allocation (final)

| Surface | Content |
|---|---|
| tmux `status-right` | System metrics only (CPU%/MEM%/DISK%/GPU%/load). No git. No time. |
| tmux pane header (`pane-border-status`) | **OFF** — no per-pane header. Avoids duplication with per-pane shell prompt. |
| Starship prompt (zsh) | cwd, **git modules on** (branch, dirty, ahead/behind, status), exit code, duration, jobs |
| claude-statusline | model, context %, cost, GPU util, load, branch + dirty glyph |
| copilot-status-beautifier | model, context %, req count, tokens, duration, project + branch/dirty (default-on segments) |
| Mac terminal clipboard (via OSC 52) | All yanks from VM tmux + `/copy` from claude/copilot |
| Mac clipboard history daemon | Maccy (or Raycast if the user later switches) |

---

## 4. Subtrack 1 — Host telemetry

### 4.1 Goal
One unified tmux status segment that shows CPU%, RAM%, DISK%, GPU%, and 1-min load. Sub-30 ms refresh cost. Silent on missing hardware.

### 4.2 Design

Replaces the existing `bin/host-health.sh` with a single `bin/sysstat.sh`:

```
CPU 23% · MEM 18G/108G (16%) · DISK 42% · GPU 12% 3.4G/16G · L 1.2
```

Color-coded per threshold, catppuccin palette (existing convention carried from `host-health.sh`):

| Metric | Gray | Yellow | Red |
|---|---|---|---|
| CPU% | < 50 | 50–80 | > 80 |
| MEM% free | > 25 | 10–25 | < 10 (or MemAvailable < 1 GiB) |
| DISK% root | < 80 | 80–95 | > 95 |
| GPU% | < 70 | 70–90 | > 90 |
| Load | < 10 | 10–30 | > 30 |

### 4.3 Snappiness strategy

| Metric | Source | Cost | Technique |
|---|---|---|---|
| CPU% | `/proc/stat` delta | ~1 ms | Cache prior sample at `/tmp/sysstat.cpu.state`; compute delta on each call |
| RAM% | `/proc/meminfo` `MemAvailable` vs `MemTotal` | ~1 ms | Single awk pass |
| DISK% | `df -P /` | ~5 ms | Single fork, wrapped in `timeout 1s` to survive hung NFS |
| GPU% | `/tmp/nvidia-stats` written by background daemon | ~1 ms | Never fork `nvidia-smi` inline — too slow |
| Load | `/proc/loadavg` | < 1 ms | `read` builtin |

Total fork count per `status-interval`: **one** (sysstat.sh). No regression vs current host-health.sh.

### 4.4 `bin/nvidia-daemon.sh`

Runs `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits -l 2` in a loop, redirecting to `/tmp/nvidia-stats`. Installed as `systemd --user` service (`nvidia-daemon.service.tpl`), autostarts, stops cleanly, silent-exit if driver absent.

sysstat.sh reads the file; if absent or older than 30 s, omits the GPU segment entirely (zero-config failure on hosts without the driver, including ld5 today).

### 4.5 Integration

- `tmux/tmux.conf.local.tpl` — replaces the existing host-health managed block:
  ```
  # >>> sysstat segment (managed) >>>
  set-option -ga status-right " #(__HOME__/bin/sysstat.sh)"
  # <<< sysstat segment (managed) <<<
  ```
- `set -g status-interval 5` — drop from default (15 s) for livelier CPU% feedback. Total cost: ~0.4% of one core. Negligible.
- `sync.sh` `BIN_SCRIPTS` — remove `host-health.sh`, add `sysstat.sh`, `nvidia-daemon.sh`.
- `install.sh` — generates `nvidia-daemon.service` from template, `systemctl --user enable --now nvidia-daemon.service` on hosts with `/proc/driver/nvidia` present.

### 4.6 Rollback

`git revert` of the power-tui phase-1 commit restores `host-health.sh`. Disabling the systemd unit on ld5 is one `systemctl --user disable --now` call.

---

## 5. Subtrack 2 — Shell awareness

### 5.1 Shell history — atuin

`atuin`, local-only SQLite history DB at `~/.local/share/atuin/history.db`. Configuration lives at `dotfiles/config/atuin/config.toml`.

- Sync server: disabled (`auto_sync = false`).
- Ctrl-R rewire: on.
- Up-arrow rewire: off (`--disable-up-arrow` at init time). Plain Up walks linear per-session history as expected.
- Filter mode default: `session` — pressing Ctrl-R first shows your current session, tab through to per-cwd and global.

Installed via `bin/install-user-bins.sh` (productivity-phase install script). Shell init loads via zsh turbo-plugin path.

### 5.2 Shell history export

Hourly `bin/state-snapshot.sh` (see subtrack 4):

```
age -p < ~/.local/share/atuin/history.db > ~/lin_code/state/atuin/history.db.age
# passphrase read from ~/.config/age/state-passphrase (mode 600, gitignored)
```

Writes only if the DB has changed (`sqlite3 ... PRAGMA user_version` tracked). Commit happens only if the ciphertext changed.

### 5.3 Per-pane tmux log — `pipe-pane`

**Default mode: A (opt-in toggle).**

- `prefix+L` toggles `pipe-pane -o "cat >> ~/logs/tmux/$(date +%Y/%m/%d)/S-#S_W-#I_P-#P.log"` on the focused pane.
- One file per pane per day. Directory pre-created on first toggle.
- Status indicator (small `[L]` glyph in window name when any pane in the window has logging active).
- `logrotate.d/tmux-logs` config committed to dotfiles, installed to `/etc/logrotate.d/` via `install.sh` (one-time sudo or manual copy). Rotates daily, gzip, keep 30 days.

**Opt-in mode: B (auto-on-shell, auto-off-TUI).**

- `prefix+M-L` (prefix + Meta-L) toggles mode B globally.
- Implementation: zsh `preexec` hook inspects command; if it's in `{vim,nvim,htop,btop,lazygit,less,more,watch,top,claude,copilot,man,yazi,broot}`, runs `tmux pipe-pane` (no args → disables) before exec, and re-runs the logging `pipe-pane -o "..."` in `precmd` after return.
- Fragile on nested shells (e.g. `bash -c 'nvim foo'`), documented as a known limitation. Covers 95% of interactive workflow.

### 5.4 Clipboard

Chain: VM tmux yank → `tmux-yank` + OSC 52 → Mac terminal passthrough → Mac clipboard → Maccy (or Raycast) history.

- `tmux/tmux.conf.local.tpl` additions:
  - `set -g set-clipboard on` — explicit OSC 52 propagation (belt-and-suspenders with `tmux-yank`).
  - `allow-passthrough on` — already present.
- Mac-side: Maccy installed via Homebrew in the eventual Mac dotfiles. Menubar. No VM-side history daemon.
- Covers Claude `/copy` and Copilot `/copy` because both emit OSC 52 directly.

### 5.5 TTY recording

- `asciinema` installed to `~/.local/bin` (Tier B).
- Alias `rec='asciinema rec'` in `shell/zshrc.d/40-aliases.zsh`. Not auto-run.
- `bin/wt claude --record` and `bin/wt copilot --record` — optional flags. Wrap the agent launch in `asciinema rec --quiet /tmp/wt-<agent>-<session>.cast` and on session end, move to `~/lin_code/state/recordings/<agent>/<session>.cast`. LFS-tracked.
- `vhs` installed to `~/.local/bin` for demo-gif authoring. No integration.

---

## 6. Subtrack 3 — Session continuity

### 6.1 Already wired (verified, carried forward)

- `tmux-plugins/tmux-resurrect` + `tmux-plugins/tmux-continuum` via tpm.
- `@continuum-save-interval '5'`, `@continuum-restore 'on'`, `@continuum-boot 'on'`.
- `@resurrect-capture-pane-contents 'on'` for saves. Restore with pane-contents disabled (3.5a↔3.2a format incompatibility noted in CLAUDE.md).
- `systemd --user tmux.service.tpl` for boot autostart.
- `mode-keys vi`, vim-style pane nav (`h/j/k/l` under prefix), resize (`H/J/K/L -r`), vi copy-mode (`v/V/y`).
- `mouse on`, Shift-drag bypass for native select, MouseDragEnd copies via xclip + OSC 52.
- `tmux-plugins/tmux-yank` with `@yank_selection_mouse 'clipboard'`.
- `Morantron/tmux-fingers` for pattern-hint capture.
- `sainnhe/tmux-fzf` for session/window/pane picker (`prefix+f`).
- `tmux-plugins/tmux-open`.

### 6.2 Copilot CLI save/restore (new)

Mirrors the existing claude pipeline.

**`bin/tmux-save-copilot-sessions`** — post-save hook.

- Walks `~/.copilot/session-state/*/inuse.*.lock`.
- Parses PID from the lock filename (`inuse.<pid>.lock`).
- Maps PID → tmux pane by walking `/proc/<pid>/status` PPID chain and comparing with the output of `tmux list-panes -a -F '#{pane_pid} #{pane_id}'`.
- Rewrites the tmux-resurrect save file, replacing the saved command `copilot` with `copilot --resume=<uuid> --allow-all-tools` for each matching pane (same pattern as claude).
- Also emits `~/.tmux/resurrect/copilot-sessions.txt` as a backup map.

**`bin/tmux-copilot-restore`** — per-pane restore script.

- Triggered via `@resurrect-processes 'copilot->__HOME__/bin/tmux-copilot-restore ...'`.
- Unsets env leaks: `COPILOT_*`, `GH_COPILOT_*`, `GITHUB_COPILOT_*` — analogous to the Claude `CLAUDE_CODE_*` cleanup.
- Removes stale `~/.copilot/session-state/<uuid>/inuse.*.lock` older than 30 s (crashed-lock cleanup).
- Runs `copilot --resume=<uuid> --allow-all-tools` via `tmux respawn-pane` or pane-send-keys (matching the technique used by `tmux-claude-restore`).

**Hook chain in `tmux.conf.local.tpl`:**

```
set -g @resurrect-hook-post-save-all '__HOME__/bin/tmux-save-claude-sessions; __HOME__/bin/tmux-save-copilot-sessions'
set -g @resurrect-processes 'claude->__HOME__/bin/tmux-claude-restore copilot->__HOME__/bin/tmux-copilot-restore ssh vim nvim htop man less tail top watch'
```

### 6.3 Worktree integration — `bin/wt` (work-side only)

Scope: `~/lin_code/` only. `bin/wt` refuses to run unless cwd is under `~/lin_code/` or `--repo <path>` is explicitly inside it.

Central worktree layout: `~/lin_code/wt/<repo>/<branch>/`.

| Subcommand | Behavior |
|---|---|
| `wt add <branch>` | `git worktree add ~/lin_code/wt/<repo>/<branch>/ <branch>` (creates branch if missing); `tmux new-window -n "<repo>/<branch>" -c <worktree-path>` |
| `wt ls` | Lists all worktrees across `~/lin_code/*` repos: path, branch, last-commit, dirty flag. Pipe-friendly for fzf |
| `wt jump` | `wt ls \| fzf` → `tmux select-window -t <repo>/<branch>` |
| `wt claude <branch>` | `wt add` + launches `claude --dangerously-skip-permissions` in the new window; registers with `tmux-save-claude-sessions` |
| `wt copilot <branch>` | `wt add` + launches `copilot --allow-all-tools` (uses `copilot-fork` when `--fork-from <session>` is passed) |
| `wt stack <base-branch>` | `wt add` + `spr track` in the new worktree |
| `wt submit` | From inside a worktree: runs `spr diff` → creates/updates stacked PRs |
| `wt sl` | From inside a worktree: `git sl` (git-branchless stacked log) |
| `wt prune` | Removes worktrees whose branches are merged (with confirmation) |
| `wt claude --record <branch>` / `wt copilot --record <branch>` | Same as `wt claude` / `wt copilot` but wraps the agent process in `asciinema rec` and moves the resulting `.cast` file into the state repo on session end |

Tmux key bindings (added as a managed block in `tmux.conf.local.tpl`):

| Key | Action |
|---|---|
| `prefix+w` | `display-popup -E "wt jump"` |
| `prefix+W` | Prompt for branch name, then `wt add` |
| `prefix+C-c` | Prompt for branch name, then `wt claude` |
| `prefix+C-p` | Prompt for branch name, then `wt copilot` |

### 6.4 YOLO resume + launch

Every Claude / Copilot invocation — fresh or resumed — carries its bypass flag:

- Claude: `--dangerously-skip-permissions` (belt-and-suspenders with `~/.claude/settings.json` `skipDangerousModePermissionPrompt: true`).
- Copilot: `--allow-all-tools`.

Flag-only, per-invocation. Never set as an env var so non-AI processes in the same shell aren't affected. Safe because all changes land as revertible commits via the session-end hook.

### 6.5 Zsh vi-mode

`jeffreytse/zsh-vi-mode` plugin loaded via zinit turbo (async). Adds:
- Visible mode indicator in the cursor shape (block/beam).
- Surround text objects (`cs"'` etc.) in command-line editing.
- Better escape handling for mode transitions.
- Zero blocking startup cost (turbo).

### 6.6 Mouse integration (preserved, no changes)

Current bindings stay exactly as-is:
- `set -g mouse on` — click-to-select-pane, click-window-in-status-to-switch, drag-pane-borders-to-resize, wheel enters copy-mode.
- `tmux_conf_copy_to_os_clipboard=true` — OSC 52 pipe on yank.
- Shift+drag bypass for native terminal select.
- `MouseDragEnd1Pane` copies to xclip + OSC 52.

Zero additional bindings. Zero snappiness cost (mouse events are kernel-level and cheap). Verification smoke test in acceptance criteria.

### 6.7 Scroll + copy-mode polish

No changes to existing bindings. Defaults are already:
- `prefix+[` enters copy-mode.
- `C-u` / `C-d` page up/down.
- `/` and `?` search.
- `v` begins selection, `V` line-select, `y` yank.

---

## 7. Subtrack 4 — Artifact durability

### 7.1 State repo — `~/lin_code/state/`

Private GitHub repo under the LinkedIn work account. Git LFS enabled on first commit.

Layout:

```
state/
├── .gitattributes              # LFS patterns
├── README.md                   # Decryption instructions, layout guide
├── claude/
│   └── projects/               # rsync of ~/.claude/projects/ (JSONL sessions + metadata)
├── copilot/
│   ├── session-state/          # rsync of ~/.copilot/session-state/
│   └── session-store.db        # copy of ~/.copilot/session-store.db (LFS)
├── atuin/
│   └── history.db.age          # age-encrypted atuin DB
├── tmux/
│   └── resurrect/              # hourly snapshot of ~/.tmux/resurrect/ dumps
├── logs/
│   └── YYYY-MM-DD.tar.gz.age   # age-encrypted daily rollup of ~/logs/tmux/
├── recordings/                 # asciinema .cast files (LFS)
└── snapshots/
    └── <hostname>/             # per-host inventory
        ├── lscpu.txt
        ├── lstopo.txt
        ├── lsblk.txt
        ├── lspci.txt
        ├── /etc/os-release
        ├── uptime.txt
        └── mounts.txt
```

### 7.2 Commit / push policy

- **Commit-only, never auto-push.** Both the hourly timer and the Claude/Copilot session-end hook commit locally and stop.
- User pushes manually when ready, protecting PR-linked branches from half-baked auto-commits.
- The state repo's default branch (`master`) has no pre-push hook; push behavior is entirely under the user's control.

### 7.3 `bin/state-snapshot.sh`

Single idempotent script:

1. Ensure repo exists (`git init`, `git lfs install` once-per-machine if needed — but only if LFS binary is available; warn otherwise).
2. rsync each source directory into the repo layout above.
3. Encrypt sensitive buckets:
   - `age -p -o atuin/history.db.age < ~/.local/share/atuin/history.db` — passphrase from `~/.config/age/state-passphrase`.
   - Daily log rollup: `tar czf - ~/logs/tmux/<today>/ | age -p > logs/<today>.tar.gz.age`.
4. Commit-time LFS detection (see 7.4).
5. Pre-commit abort on secret patterns (see 7.5).
6. `git commit -m "snapshot <hostname> <timestamp>"`. Skip if `git diff --cached --quiet`.
7. Never push.

### 7.4 Commit-time LFS detection (no per-repo `git lfs install`)

User has `git-lfs` installed once per machine manually. Per-repo `lfs install` is not required by design.

Hook logic (inside `state-snapshot.sh` and `session-end-autocommit.sh`):

```
staged=$(git diff --cached --name-only)
tracked_now=$(git lfs track 2>/dev/null | awk '/Tracking/{print $2}')
added=()
for f in $staged; do
  [[ -f $f ]] || continue
  if file --mime-encoding -- "$f" | grep -q ': binary$'; then
    ext="${f##*.}"
    [[ -n $ext && $ext != "$f" ]] || continue
    pat="*.${ext}"
    grep -qxF "$pat" .gitattributes 2>/dev/null || {
      git lfs track "$pat"
      added+=("$pat")
    }
  fi
done
if ((${#added[@]})); then
  git add .gitattributes
  git add -u -- .
fi
```

Effect: any binary file committed for the first time triggers an LFS tracking rule for its extension. Subsequent binaries of the same extension pass through transparently.

### 7.5 Secret-pattern abort

Before `git commit`, state-snapshot and session-end hooks grep cleartext staged files for:

```
ghp_
gho_
github_pat_
sk-[a-zA-Z0-9]{20,}
AKIA[0-9A-Z]{16}
```

On match: abort commit (`exit 1` with loud journald log entry). Working tree left intact for the user to clean. `detect-private-key` covers the PEM-key tripwire via the separate pre-commit framework (for repos that opt into pre-commit).

### 7.6 Encryption — age, passphrase mode

- Symmetric passphrase at `~/.config/age/state-passphrase` (mode 600, gitignored anywhere).
- Memorable passphrase (user-chosen).
- Encrypted buckets: atuin DB, tmux log rollups.
- Cleartext buckets: Claude session JSONL, Copilot session state, tmux-resurrect dumps, per-host inventories.
  - Rationale: these are your own prompts/commits/host config, not secret. The encrypted buckets are those that may contain shell commands or output that inadvertently pasted a token.

### 7.7 Schedule

- `systemd/state-snapshot.service.tpl` + `systemd/state-snapshot.timer.tpl` — templates with `__HOME__`/`__USER__` placeholders.
- `install.sh` generates user units into `~/.config/systemd/user/` and runs `systemctl --user enable --now state-snapshot.timer`.
- `OnCalendar=hourly`, `Persistent=true` (catches up after reboots).
- `journalctl --user -u state-snapshot.service` for troubleshooting.

### 7.8 Session-end auto-commit (Claude + Copilot)

Wiring:

- Claude: `SessionEnd` hook in `~/.claude/settings.json` → `bin/session-end-autocommit.sh claude <session-id>`.
- Copilot: a `trap EXIT` wrapper inside `bin/wt copilot` (and inside an optional standalone `bin/copilot` launcher) calls `session-end-autocommit.sh copilot <session-id>` on shell exit. This is the chosen path because Copilot CLI's native hook surface is less mature than Claude's; a wrapper works uniformly for wt-launched sessions and manual invocations alike.

The script:

1. Detects cwd's git repo root.
2. If not in a git repo, exits 0 silently.
3. If clean working tree, exits 0 silently (nothing to commit).
4. Runs the commit-time LFS detection from 7.4.
5. Runs the secret-pattern abort from 7.5.
6. `git add -A && git commit -m "session <agent> <short-id>: <one-line summary>"`.
7. **No push.** No pre-commit invocation. No Co-Authored-By line.

The "one-line summary" is derived from `git diff --cached --stat` — e.g., `wip: bin/host-health.sh +14 -3, README.md +2 -0`.

### 7.9 What's explicitly NOT in this phase

- Personal-side state capture (`~/my_stuff/state/`) — deferred.
- Sync to external storage (restic, rclone, S3) — deferred.
- Claude-side session summarization by another agent — deferred.
- State repo web UI — skipped.

---

## 8. Subtrack 5 — Project / repo-state visibility

### 8.1 Tool picks (final)

| Tool | Tier | Role |
|---|---|---|
| **lazygit** | Tier B (~/.local/bin) | Daily git TUI. `prefix+g` → tmux popup. `lg='lazygit'` alias. Config at `dotfiles/config/lazygit/config.yml` uses delta as external pager. |
| **delta** | Tier B | `core.pager`; syntax-highlighted side-by-side diff. Catppuccin-delta theme committed. |
| **difftastic** | Tier B | `GIT_EXTERNAL_DIFF` for semantic diffs. `git dft` alias. |
| **gh** | Tier A (tdnf) | PR create/review/merge on `~/lin_code/`. Not authed in `~/my_stuff/`. |
| **gh-dash** | Tier B | Work-only dashboard. `prefix+d` → popup. Config at `dotfiles/config/gh-dash/config.yml`. |
| **spr** | Tier B | Stacked PRs without Graphite. |
| **git-branchless** | Tier B | Local stacked-log, `git move`, `git undo`. |
| **git-absorb** | Tier B | `gfix='git absorb --and-rebase'`. |
| **pre-commit** | Pipx | Per-repo framework. Default hooks: `trailing-whitespace`, `end-of-file-fixer`, `check-added-large-files` (forces LFS), `detect-private-key`. **Explicitly excluded: gitleaks.** |
| **onefetch** | Tier B | On-demand `just repo-info` recipe. Not auto-on-cd (snappiness). |
| **scc** | Tier B | `clx='scc .'` alias. |
| **git-who** | Tier B | Interactive blame-plus. |
| **git-sizer** | Tier B | One-off audit tool. No alias. |
| **git-filter-repo** | Tier B | Install-only for occasional surgery. |
| **git-lfs** | Tier A (tdnf) | Required; user installs once per machine manually. |
| **tig** | — | OUT (lazygit covers). |
| **gitui** | — | OUT (lazygit sufficient at current repo sizes). |
| **ghq, mani, mr, mu-repo** | — | OUT (few repos). |
| **sapling, graphite, ghstack** | — | OUT (Graphite not allowed; workflow uses spr + worktrees). |
| **gitleaks** | — | OUT (explicit user call). |
| **lefthook** | — | OUT (pre-commit has wider ecosystem). |
| **commitizen** | — | DEFER. |

### 8.2 Git state surfaces

- **Starship:** `git_branch`, `git_commit`, `git_state`, `git_status` modules all enabled. Config at `dotfiles/config/starship.toml`, symlinked by `install.sh` to `~/.config/starship.toml`.
- **claude-statusline:** existing branch shown; add dirty glyph (`*` if `git status --porcelain` non-empty). Cached (claude-statusline runs on every model turn).
- **copilot-status-beautifier:** default git segment (`project · branch clean|dirty`) stays on.
- **tmux status-right:** no git. System metrics only.
- **tmux pane header:** off.

### 8.3 Two-identity git config

`dotfiles/git/gitconfig` gains:

```
[includeIf "gitdir:~/my_stuff/"]   path = ~/.gitconfig-personal
[includeIf "gitdir:~/lin_code/"]   path = ~/.gitconfig-work
```

Files:
- `dotfiles/git/gitconfig-personal` — committed. Identity: `asamadiya <asamadiya@users.noreply.github.com>`.
- `dotfiles/git/gitconfig-work.example` — committed **template only**, with placeholder `__WORK_EMAIL__`. Contains no real work email.
- `~/.gitconfig-work` — local-only, never committed. User copies from the `.example` template on each work host and substitutes the real LinkedIn email. Listed in `.gitignore`.

`install.sh` symlinks `dotfiles/git/gitconfig` and `dotfiles/git/gitconfig-personal` into place. `~/.gitconfig-work` is the user's responsibility per host (one-off, documented in README).

### 8.4 `.gitattributes` LFS template

`dotfiles/config/gitattributes-lfs-template` contains the default LFS patterns:

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

`bin/lfs-template-apply <repo>` copies + commits.

---

## 9. File and wiring inventory

### 9.1 New scripts (`dotfiles/bin/`)

| Script | Purpose |
|---|---|
| `sysstat.sh` | tmux status segment — CPU/MEM/DISK/GPU/load unified |
| `nvidia-daemon.sh` | Background GPU telemetry writer for `/tmp/nvidia-stats` |
| `tmux-save-copilot-sessions` | post-save hook, maps panes → copilot session IDs |
| `tmux-copilot-restore` | per-pane restore script for copilot |
| `wt` | Worktree + agent orchestrator (work-only) |
| `state-snapshot.sh` | Hourly state repo snapshot / commit |
| `session-end-autocommit.sh` | Claude/Copilot session-end auto-commit hook |
| `lfs-template-apply` | Copies `.gitattributes` LFS template to target repo |

### 9.2 Removed scripts

- `bin/host-health.sh` — superseded by `sysstat.sh`.

### 9.2b New docs

| File | Purpose |
|---|---|
| `docs/guides/2026-04-19-observability-user-guide.md` | End-user guide: keybindings cheatsheet, daily workflows (start parallel work, end session, recover from crash), per-command reference (`wt`, `sysstat`, `lazygit`, `state-snapshot`, session-end autocommit), troubleshooting, "before you push" checklist, disaster recovery (state repo decrypt, worktree recovery). Written as the final deliverable of the implementation plan, once behavior is concrete. |

### 9.3 New config files (`dotfiles/config/`)

| File | Purpose |
|---|---|
| `starship.toml` | Prompt config with git modules |
| `atuin/config.toml` | atuin behavior |
| `lazygit/config.yml` | lazygit config using delta pager |
| `gh-dash/config.yml` | Work-repo PR/issue sections |
| `gitattributes-lfs-template` | LFS extension list |
| `pre-commit-template.yaml` | Default pre-commit hook set (no gitleaks, keep detect-private-key) |

### 9.4 New systemd units (`dotfiles/systemd/`)

| Template | Purpose |
|---|---|
| `nvidia-daemon.service.tpl` | Background GPU telemetry writer |
| `state-snapshot.service.tpl` | Runs `bin/state-snapshot.sh` |
| `state-snapshot.timer.tpl` | `OnCalendar=hourly Persistent=true` |

### 9.5 Edits

- `tmux/tmux.conf.local.tpl`:
  - `status-interval 5`
  - `sysstat` managed block replaces `host-health` block
  - `set -g set-clipboard on`
  - Resurrect hook chain with both claude + copilot save hooks
  - Resurrect-processes list gains copilot entry
  - `wt` key bindings managed block
  - `prefix+L` / `prefix+M-L` pane-logging bindings managed block
- `shell/zshrc.d/` (new, modular) — scaffolded with stubs; shell stack filled in productivity phase.
- `shell/bashrc` — minor: source `shared.sh` for cross-shell env.
- `git/gitconfig` — adds `includeIf` blocks; references sibling personal/work files.
- `claude/settings.json.tpl` — adds `SessionEnd` hook pointing at `bin/session-end-autocommit.sh claude`.
- `install.sh`:
  - Symlink `~/.bashrc.d/`, `~/.zshrc.d/`, `~/.config/starship.toml`, `~/.config/atuin/config.toml`, `~/.config/lazygit/config.yml`, `~/.config/gh-dash/config.yml`.
  - Generate + enable systemd user units (`nvidia-daemon`, `state-snapshot`, existing tmux).
  - Install `logrotate.d/tmux-logs` (optional, sudo-guarded).
- `sync.sh`:
  - `BIN_SCRIPTS` gains sysstat.sh, nvidia-daemon.sh, tmux-save-copilot-sessions, tmux-copilot-restore, wt, state-snapshot.sh, session-end-autocommit.sh, lfs-template-apply.
  - Remove host-health.sh from the array.
- `README.md`, `CLAUDE.md`, `env.txt`:
  - README — observability section added summarizing surfaces.
  - CLAUDE.md — Key Scripts table updated.
  - env.txt — rewritten from real state post-install; documents AzL3 / kernel 6.6 / tool versions.
- `CHANGELOG.md` — one block per commit as each subtrack lands.

---

## 10. Acceptance criteria

On `power-tui` branch, ld5 as primary test host:

1. **Tmux status bar.** `sysstat.sh` renders `CPU X% · MEM X/108G (X%) · DISK X% · [GPU ...]? · L X` every 5 s. No GPU segment on ld5 until driver lands. Wall cost per refresh < 30 ms.
2. **tmux nvidia-daemon.** `systemctl --user status nvidia-daemon` → inactive (no driver) or active with `/tmp/nvidia-stats` fresh every 2 s.
3. **Claude resurrect.** Exit Claude in a pane, kill tmux server, restart via `systemd --user start tmux`, continuum restores; pane comes back with `claude --resume=<id> --dangerously-skip-permissions` as its process.
4. **Copilot resurrect.** Same flow for `copilot --resume=<id> --allow-all-tools` in a copilot pane.
5. **Worktree.** `cd ~/lin_code/<repo> && wt add feature-foo` creates the worktree at `~/lin_code/wt/<repo>/feature-foo/` and a new tmux window `<repo>/feature-foo`. `wt ls` lists it. `wt jump` fzf-jumps. `wt prune` after merge removes it.
6. **wt + agents.** `wt claude feature-bar` opens a new window + worktree + Claude session. `wt copilot feature-baz` same for Copilot. Both launch with YOLO flags.
7. **Session-end autocommit.** End a Claude session mid-change. Run `git log -1` in the worktree: commit is present, message is concise, no Co-Authored-By, no push.
8. **LFS autodetect.** Commit a PNG via the autocommit flow: `.gitattributes` gains `*.png filter=lfs ...`, file is LFS-tracked.
9. **State snapshot.** `systemctl --user start state-snapshot.service` → manual trigger → commit in `~/lin_code/state/` with updated `claude/`, `copilot/`, `tmux/resurrect/`, `atuin/history.db.age`. Hourly timer shows `active` in `systemctl --user list-timers`.
10. **Secret abort.** Paste a line containing `ghp_abc123...` into a file inside the state repo, manually add, invoke `bin/state-snapshot.sh`: abort with loud log, no commit.
11. **Starship.** Interactive zsh prompt in a dirty repo shows branch + dirty glyph + status code + duration. `time zsh -ic exit` < 100 ms.
12. **Claude statusline.** Dirty indicator appears in the claude statusline; branch unchanged; no duplication with the prompt (different screen region).
13. **Copilot statusline.** `project · branch clean|dirty` segment on; no other duplication.
14. **Clipboard.** In tmux vi-mode, `v`-select-`y` on VM → paste on Mac via Cmd-V → text lands. Claude `/copy` in a pane → same. Mouse-drag in pane → same. Shift-drag bypasses for native-select.
15. **Mouse.** Click to focus pane, click-on-status-window switches, drag-pane-border resizes, wheel-in-pane scrolls.
16. **Pane logs mode A.** `prefix+L` on a shell pane → `~/logs/tmux/YYYY/MM/DD/S-*_W-*_P-*.log` grows as commands run. `prefix+L` again stops. Repeat in mode B: `prefix+M-L` enables global auto; running `claude` in a pane auto-disables logging for the claude lifetime.
17. **lazygit.** `prefix+g` → popup, diffs render via delta theme, rebase works.
18. **gh-dash.** In a `~/lin_code/` repo: `prefix+d` → popup, PR panels render. In a `~/my_stuff/` repo: gracefully reports "not authenticated" without crash.
19. **Two-identity.** `cd ~/my_stuff/dotfiles && git config user.email` → personal. `cd ~/lin_code/somerepo && git config user.email` → work.
20. **Portability.** `bootstrap.sh` + `install.sh` on a fresh AzL3 VM reproduce the setup; no hardcoded ld5 paths.
21. **User guide exists.** `docs/guides/2026-04-19-observability-user-guide.md` is written as the final step of the implementation plan. Covers every new keybinding, every `wt` subcommand, the pane-logging modes A/B, the auto-commit + state-snapshot flows, "before you push" checklist, state-repo decryption, and worktree recovery. Verified complete by a fresh reader following it end-to-end on ld5 without needing the spec.

---

## 11. Rollback strategy

- All repo changes on branch `power-tui`; `git checkout master` restores.
- `systemd --user disable --now nvidia-daemon.service state-snapshot.timer state-snapshot.service` undoes schedulers.
- `rm ~/.config/starship.toml ~/.config/atuin/config.toml ...` undoes config symlinks (idempotent on next `install.sh`).
- `rm -rf ~/lin_code/state` removes the state repo (user data loss risk — confirmation required).
- Each subtrack is a separate commit on `power-tui`; individual `git revert` possible per subtrack.

---

## 12. Open questions / risks

| # | Risk / question | Mitigation |
|---|---|---|
| 1 | tmux-continuum auto-restore is fragile with pane-contents disabled; a failed resurrect can leave panes in broken state | Documented in CLAUDE.md; manual `tmux kill-server && systemctl --user restart tmux` recovery. No change in this phase. |
| 2 | pipe-pane auto-mode B preexec hook may misfire on nested shells | Documented as known limitation; default is mode A (opt-in toggle) which has no such fragility. |
| 3 | Secret-pattern abort has no gitleaks; could miss novel token prefixes | Acceptable per user call. Add to the regex list reactively if a new prefix is ever seen in the wild. |
| 4 | age passphrase stored on disk at `~/.config/age/state-passphrase` | Same blast radius as anything else on the dev VM; acceptable for personal dev machine. |
| 5 | Commit-time LFS detection by extension may miss binaries with uncommon extensions or no extension | Binary detection via `file --mime-encoding` as primary check; extension just picks the tracking pattern. For no-extension binaries, logs a warning and skips LFS tracking. |
| 6 | No auto-push means state repo may drift far from remote | User's explicit call; prompted `git status` sweep could be added in a future phase if desired. |
| 7 | `wt` must run inside `~/lin_code/` only — a user-error in `~/my_stuff/` refuses but may confuse | Clear error message; documented in `wt --help`. |
| 8 | `spr` commit-trailer convention (`git-spr-id`) is slightly invasive | Acceptable tradeoff given Graphite unavailable. Can always fall back to manual gh PR stacks. |
| 9 | Mac-side (Maccy, terminal config) not covered here | Deferred to productivity-phase or Mac-side-dotfiles spec. |
| 10 | NVIDIA driver install not in scope | ld5 runs silent on GPU until user decides to land the driver. sysstat gracefully omits the GPU segment. |

---

## 13. Out of scope (for this phase only)

- Productivity layer (shell tool installs, bashrc.d refactor, daily-driver CLI replacements).
- Neovim setup.
- Mac-side dotfiles (Brewfile, Ghostty/WezTerm config, SSH config, Raycast/Maccy install).
- NVIDIA driver / CUDA install.
- Agentic-loop tools (aider, llm, ollama).
- Observability dashboard (netdata).
- Personal-side state capture.
- Cross-host unified dashboards across ld4 + ld5.

These may each be follow-up specs.

---

## 14. Related memories

- `user_profile.md`
- `feedback_git_first.md`
- `feedback_tool_selection.md`
- `feedback_terse_responses.md`
- `project_my_stuff_layout.md`
- `project_shell_stack.md`
- `project_state_repo.md`
- `feedback_yolo_resume.md`
