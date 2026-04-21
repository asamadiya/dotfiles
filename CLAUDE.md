# CLAUDE.md — dotfiles repo

## What This Is

Personal dotfiles repo for a Linux dev box with GPU.
Manages shell, tmux, git, systemd, and Claude Code configuration with full
session persistence across VM restarts including Claude Code conversation
restoration.

## Repo Structure

```
dotfiles/
├── shell/              # bashrc, bash_profile, profile
├── git/                # gitconfig
├── tmux/               # oh-my-tmux .tmux.conf.local.tpl + pre-migration backup
├── bin/                # Scripts: keepalive, claude session save/restore, statusline, branch guard
├── systemd/            # tmux.service.tpl (template — install.sh generates with real paths)
├── claude/             # Claude Code settings, keybindings, rules, agents, global CLAUDE.md
│   ├── settings.json.tpl # Full settings with permissions, hooks, env vars, plugins
│   ├── keybindings.json
│   ├── rules/persona.md
│   ├── agents/         # Custom + GSD agents
│   └── CLAUDE.md       # Global CLAUDE.md (symlinked to ~/CLAUDE.md)
├── bootstrap.sh        # Fresh VM setup — builds tmux 3.5a, installs prerequisites
├── install.sh          # Symlinks dotfiles into place, generates systemd service
├── sync.sh             # Bidirectional sync (pull/push) between live system and repo
├── env.txt             # Tool version reference
├── CHANGELOG.md        # Full history of issues found and fixed (13+ issues)
└── README.md           # User guide with keybindings, architecture, troubleshooting
```

## Key Scripts

| Script | Purpose |
|--------|---------|
| `bootstrap.sh` | Installs everything on a fresh VM (libevent, tmux 3.5a, oh-my-tmux, TPM, claude) |
| `install.sh` | Symlinks dotfiles, generates systemd service from template |
| `sync.sh` | `--push` (repo->live), no args (live->repo + diff), `--commit` (live->repo + commit) |
| `bin/tmux-claude-restore` | Resurrect inline strategy — resumes claude sessions by ID |
| `bin/tmux-save-claude-sessions` | Post-save hook — maps panes to claude session IDs |
| `bin/tmux-copilot-restore` | Resurrect inline strategy — resumes copilot sessions by ID (unsets COPILOT_* env leaks, cleans stale locks) |
| `bin/tmux-save-copilot-sessions` | Post-save hook — maps panes to copilot session IDs, rewrites saved cmd to include `--resume=<uuid> --allow-all-tools` |
| `bin/claude-statusline.sh` | Statusline: model, git branch + dirty glyph, GPU, load, cost, context bar |
| `bin/claude-guard-main.sh` | PreToolUse hook — blocks Edit/Write on main/master branch |
| `bin/sysstat.sh` | Unified tmux status segment: CPU%/MEM/DISK/GPU/load with per-metric color escalation |
| `bin/nvidia-daemon.sh` | systemd --user service caching nvidia-smi telemetry to /tmp/nvidia-stats (silent if driver absent) |
| `bin/wt` | Worktree orchestrator for ~/lin_code/ (add/ls/jump/prune + claude/copilot YOLO launch + stack/submit/sl) |
| `bin/session-end-autocommit.sh` | Claude/Copilot SessionEnd hook — LFS detection + secret-pattern abort, commit-only, no push, no Co-Authored-By |
| `bin/copilot-with-autocommit` | Thin `copilot` wrapper — trap EXIT runs session-end-autocommit.sh |
| `bin/state-snapshot.sh` | Hourly state-repo snapshot — rsync + asymmetric-age encryption (identity file) + LFS + secret-abort, commit-only |
| `bin/pane-log-toggle.sh` / `bin/pane-log-mode.sh` | Per-pane (prefix+L) and global (prefix+M-L) tmux logging controls |
| `bin/lfs-template-apply` | Idempotent `.gitattributes` LFS template copier for target repos |
| `bin/lint-shell.sh` | shellcheck wrapper over bin/ + tests/ |
| `bin/install-user-bins.sh` | Unified idempotent installer for all user-local CLI binaries (zsh via zsh-bin, nvim AppImage, ~35 Rust/Go binaries). No tdnf, no sudo. Version-pinned. |

## Architecture Decisions

- **oh-my-tmux** upstream `.tmux.conf` is never edited — all overrides in `.tmux.conf.local.tpl`
- **systemd service uses template** (`tmux.service.tpl`) with `__USER__`/`__HOME__` placeholders, generated at install time so it works for any user
- **tmux 3.5a built from source** because system tmux (3.2a) lacks `allow-passthrough` and `hyperlinks` for cmd+click
- **Pane contents restore disabled** (`@resurrect-capture-pane-contents on` for saving, but restore with pane contents crashes tmux 3.5a with 3.2a-format saves)
- **Claude session restore** uses a two-part system: post-save hook maps pane→session ID, inline restore strategy resumes exact conversation

## Known Issues / Gotchas

1. `bin/claude-guard-main.sh` blocks Edit/Write on main branch — use `bash` or `sed` to modify files when working on dotfiles repo itself
2. tmux-resurrect pane contents restore is incompatible across tmux major versions — if sessions don't restore, try with `@resurrect-capture-pane-contents off`
3. Claude env vars (`CLAUDE_CODE_SESSION`, `CLAUDE_CODE_ENTRY_POINT`, `CLAUDECODE`) leak into restored panes — `tmux-claude-restore` unsets all three
4. oh-my-tmux overrides `prefix+p` to paste — fixed with `#!important` binding

## Shell Quirks

- `find` is aliased to `fd` — use Glob tool instead
- `grep` is aliased to `rg` — use Grep tool instead

## Workflow

- IMPORTANT: Be terse. No hand-holding. Lead with code.
- IMPORTANT: On `main`/`master` the guard hook blocks Edit/Write. Use bash/sed for edits or work on a feature branch (e.g., `power-tui`).
- Run `sync.sh` to pull live changes, `sync.sh --commit` to commit them
- Run `sync.sh --push` to deploy repo state to live system
