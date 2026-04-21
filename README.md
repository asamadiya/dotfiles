# Dotfiles 

Power-user Linux dev box configuration. Persistent tmux sessions with Claude Code conversation restoration, oh-my-tmux with Catppuccin theme, and a fully reproducible setup via bootstrap script.

## Fresh VM Setup

```bash
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
./bootstrap.sh
```

`bootstrap.sh` builds tmux 3.5a from source, installs oh-my-tmux, TPM, Claude Code, and runs `install.sh` to symlink everything. See `env.txt` for tool version reference.

## Repo Structure

```
dotfiles/
├── shell/                  # bashrc, bash_profile, profile
├── git/                    # gitconfig (aliases, LFS, gh credential helper)
├── tmux/
│   ├── tmux.conf.local     # oh-my-tmux overrides (theme, bindings, persistence)
│   └── tmux.conf.pre-ohmytmux.bak
├── bin/
│   ├── claude-statusline.sh         # Statusline: model|branch+dirty|GPU|load|cost|context
│   ├── claude-guard-main.sh         # PreToolUse hook: blocks edits on main/master
│   ├── tmux-claude-restore          # Resurrect: resumes claude sessions by ID
│   ├── tmux-save-claude-sessions    # Post-save hook: maps panes to claude session IDs
│   ├── tmux-copilot-restore         # Resurrect: resumes copilot sessions by ID
│   ├── tmux-save-copilot-sessions   # Post-save hook: maps panes to copilot session IDs
│   ├── tmux-restore                 # Manual resurrect trigger
│   ├── keepalive.sh                 # VM keepalive daemon
│   ├── sysstat.sh                   # Unified tmux status segment: CPU%/MEM/DISK/GPU/load with color escalation
│   ├── nvidia-daemon.sh             # systemd --user service caching nvidia-smi to /tmp/nvidia-stats
│   ├── wt                           # Worktree orchestrator for ~/lin_code/ (work-only)
│   ├── session-end-autocommit.sh    # Claude/Copilot SessionEnd hook — commit-only, LFS-aware, secret-abort
│   ├── copilot-with-autocommit      # Copilot launcher w/ trap-EXIT session-end hook
│   ├── state-snapshot.sh            # Hourly state-repo snapshot (commit-only)
│   ├── pane-log-toggle.sh           # Mode-A per-pane logging toggle (prefix+L)
│   ├── pane-log-mode.sh             # Mode-B global toggle (prefix+M-L)
│   ├── lfs-template-apply           # Copy LFS .gitattributes template into target repo
│   └── lint-shell.sh                # shellcheck wrapper over bin/ + tests/
├── claude/
│   ├── settings.json       # Permissions, hooks, plugins, env vars
│   ├── keybindings.json    # Ctrl+G (git), Ctrl+K (GPU)
│   ├── CLAUDE.md           # Global instructions (symlinked to ~/CLAUDE.md)
│   ├── rules/persona.md    # Power-user persona rules
│   └── agents/             # Custom + GSD agents (15 agents)
├── systemd/
│   └── tmux.service.tpl    # Template (install.sh generates with real paths)
├── bootstrap.sh            # Fresh VM: builds tmux 3.5a, installs all deps
├── install.sh              # Symlinks dotfiles, generates systemd service
├── sync.sh                 # Bidirectional sync between live system and repo
├── env.txt                 # Tool version reference
├── CHANGELOG.md            # 20 issues found and fixed
├── CLAUDE.md               # Instructions for agents working on this repo
└── README.md
```

## Architecture

```
~/.tmux.conf       -> oh-my-tmux/.tmux.conf         (upstream, don't edit)
~/.tmux.conf.local -> dotfiles/tmux/tmux.conf.local  (all customizations)
~/.local/bin/tmux  = tmux 3.5a (built from source for hyperlink support)
/bin/tmux          = tmux 3.2a (system, unused)
```

## Tmux

**Prefix:** `C-space` | **Theme:** Catppuccin Mocha + powerline

| Key | Action |
|-----|--------|
| `prefix \|` / `prefix -` | Split h/v |
| `prefix c` | New window (inherits path) |
| `prefix h/j/k/l` | Navigate panes |
| `prefix H/J/K/L` | Resize panes |
| `prefix p/n` | Previous/next window |
| `prefix m` | Toggle mouse |
| `prefix e` / `prefix r` | Edit config / reload |
| `prefix C-s` / `prefix C-r` | Save / restore (resurrect) |
| `prefix I` | Install plugins |
| `Shift+drag` | Select text (bypasses tmux mouse) |
| `Cmd+click` | Open hyperlinks (tmux 3.5a) |

### Session Persistence

tmux-continuum auto-saves every 5 min. tmux-resurrect captures layouts, directories. Systemd auto-starts tmux on boot. Continuum auto-restores on start.

Claude Code sessions are restored to their exact conversation via session ID mapping.

## Claude Code

**Model:** Opus 4.6 (1M context) | **Thinking:** Always on | **Agent teams:** Enabled

| Keybinding | Action |
|---|---|
| `Ctrl+G` | Git status + diff |
| `Ctrl+K` | GPU utilization |
| `Shift+Tab` | Cycle permission modes |
| `Esc Esc` | Rewind to checkpoint |

### Custom Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| `security-reviewer` | opus | OWASP/CVE code review |
| `perf-profiler` | sonnet | Python/PyTorch bottleneck analysis |
| `researcher` | opus | Web + codebase deep research |
| GSD agents (12) | various | Project planning, execution, verification |

### Hooks

- **PreToolUse (Edit\|Write):** Block edits on main/master branch
- **PostToolUse:** GSD context monitor
- **Notification:** tmux display-message + terminal bell
- **SessionStart:** GSD update check

## Shell Aliases

| Alias | Command |
|-------|---------|
| `c` | `claude` |
| `cc` | `claude --continue` |
| `cr` | `claude --resume` |
| `cw` | `claude --worktree` |
| `k` | `kubectl` |

## Sync

```bash
./sync.sh              # Pull: live -> repo (show diff)
./sync.sh --commit     # Pull + commit
./sync.sh --push       # Push: repo -> live system
```

## Statusline

```
Opus 4.6 main dotfiles GPU:0% 0M/16384M L:3.73 $1.42 ████░░░░░░ 45%
```

model | git branch (cyan) | dir | GPU (magenta) | load | cost | context bar (color-coded)

## Troubleshooting

See `CHANGELOG.md` for 20 documented issues with root causes and fixes. Common ones:

- **"nobody" user in panes:** Fixed via `default-command "exec /bin/bash --login"`
- **Cmd+click broken:** Requires tmux 3.5a (`bootstrap.sh` builds it)
- **Claude nested session error:** `unset CLAUDE_CODE_SESSION CLAUDE_CODE_ENTRY_POINT CLAUDECODE`
- **Sessions not restoring:** Try `tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh` with `@resurrect-capture-pane-contents off`
- **Stuck "Restoring..." message:** `pkill -f tmux_spinner; tmux display-message ''`

## Observability (power-tui phase)

### Status surfaces

- **tmux status-right** — system metrics only (CPU% / MEM / DISK / GPU / load) via `bin/sysstat.sh`, refreshed every 5 s.
- **Starship prompt** (productivity phase) — cwd, git state (branch, dirty, ahead/behind), exit code, duration.
- **claude-statusline** — model, context %, cost, GPU, load, branch + dirty glyph.
- **copilot statusline** — model, context %, req count, tokens, duration, project + branch/dirty. Configured via `config/copilot/statusline-settings.json`.

### New key scripts

`sysstat.sh`, `nvidia-daemon.sh`, `tmux-save-copilot-sessions`, `tmux-copilot-restore`, `wt`, `session-end-autocommit.sh`, `copilot-with-autocommit`, `state-snapshot.sh`, `pane-log-toggle.sh`, `pane-log-mode.sh`, `lfs-template-apply`, `lint-shell.sh`. Retired: `host-health.sh` (superseded by `sysstat.sh`).

### Key bindings added

| Key | Action |
|---|---|
| `prefix+C-w` | fzf over worktrees, jump in tmux |
| `prefix+W` | prompt for branch → `wt add` |
| `prefix+C-c` | prompt for branch → `wt claude` (YOLO) |
| `prefix+C-p` | prompt for branch → `wt copilot` (YOLO) |
| `prefix+L` | toggle pane logging (mode A — per-pane) |
| `prefix+M-L` | toggle pane-logging mode B (auto-on shell, auto-off TUI) |

### Session auto-commit

Every Claude Code and Copilot CLI session, on exit, runs
`bin/session-end-autocommit.sh <agent> <sid>` in the agent's cwd. **Commit only — never pushes.**
Auto-adds binaries to Git LFS by extension. Aborts loudly on secret regex (`ghp_`, `gho_`, `github_pat_`, `sk-...`, `AKIA...`). No Co-Authored-By trailer.

### State repo

`~/lin_code/state/` holds Claude/Copilot sessions, atuin history (age-encrypted), tmux-resurrect dumps, tmux log rollups, per-host inventories. Hourly via `systemd --user state-snapshot.timer`. **Commit-only — never pushes.** Encryption is asymmetric age (identity at `~/.config/age/state-identity.txt`, mode 600, generated once via `age-keygen`).

For the full design rationale see `docs/superpowers/specs/2026-04-19-observability-design.md`. For daily workflows see `docs/guides/2026-04-19-observability-user-guide.md`.
