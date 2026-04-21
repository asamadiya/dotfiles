# Changelog

## 2026-04-21 — Productivity phase (branch: power-productivity)

Second phase of the power-tui overhaul — shell + CLI + neovim. Per
`docs/superpowers/specs/2026-04-21-productivity-design.md` and its plan.

**Shell stack:**
- zsh 5.8 installed via `romkatv/zsh-bin` to `~/.local/bin/zsh` (no tdnf, no sudo, no build toolchain).
- tmux default-command + default-shell flipped to `~/.local/bin/zsh`. Login shell unchanged (bash).
- Plugin manager: **zinit** (turbo-mode). Cold-start measured at ~55 ms on ld5 (target < 150 ms).
- Modular `~/.zshrc.d/00-path.zsh … 90-starship.zsh` + `95-pane-log.zsh` (from observability phase).
- Turbo plugins: `zsh-autosuggestions`, `fast-syntax-highlighting`, `zsh-completions`, `fzf-tab`.
- Eval-init: starship, atuin (cloud sync), zoxide, direnv, carapace-bin (deferred to first precmd).
- Completion layering: builtins → zsh-completions → tool-native → bashcompinit bridge → carapace-bin.

**CLI binaries** (all via `bin/install-user-bins.sh`, user-local to `~/.local/bin/`, no tdnf):
atuin 18.15.2, bat 0.26.1, btop 1.4.6, carapace 1.6.4, delta 0.19.2, difft 0.68.0,
direnv 2.37.1, duf 0.9.1, dust 1.2.4, eza 0.23.4, fd 10.4.2, fzf 0.71.0, gh 2.90.0,
gh-dash 4.23.2, git-absorb 0.9.0, git-branchless 0.10.0, git-who 1.3, hyperfine 1.20.0,
jq 1.8.1, just 1.50.0, lazygit 0.61.1, onefetch 2.21.0 (newer needs GLIBC 2.39),
procs 0.14.11, rg 15.1.0, scc 3.7.0, sd 1.1.0, spr 0.17.5, starship 1.25.0,
tldr 1.8.1, vhs 0.11.0, watchexec 2.5.1, yazi 26.1.22, yq 4.53.2, zoxide 0.9.9,
asciinema 3.2.0.

**Neovim:** both distros via `NVIM_APPNAME` isolation.
- `nvim` → NvChad v2.5 (config at `config/nvim/`, overrides in `lua/chadrc.lua`, `lua/plugins/init.lua`, `lua/mappings.lua`).
- `lv` → LazyVim (config at `config/nvim-lazy/`, overrides in `lua/plugins/user.lua`).
- nvim 0.12.1 AppImage at `~/.local/bin/nvim` (FUSE unavailable on ld5 — installer used `--appimage-extract`).

**Configs:** `config/atuin/config.toml` (cloud sync + Ctrl-R rewire),
`config/starship.toml` (two-line prompt, git modules on, language prompts off),
`config/nvim/lua/*` (NvChad overrides), `config/nvim-lazy/lua/plugins/user.lua` (LazyVim overrides).

**No tdnf calls anywhere** — every binary lands via `install-user-bins.sh` from upstream GitHub releases. Zero sudo prompts.

**Spec-vs-reality deviations absorbed into install-user-bins.sh** (full notes in execution log):
atuin/yazi → musl (glibc 2.38 vs 2.39); gh-dash/asciinema → single-file; git-absorb/branchless → musl only;
git-who asset is `gitwho_*` (no hyphen); btop has `-unknown-` segment; spr binary is `git-spr`;
onefetch pinned 2.21.0.

**Generic fetcher enhancements** to `bin/install-user-bins.sh`: optional 6th `register` arg for tag template,
`{v}`/`{V}` substitution extended to `bin_in_archive`, `*.tar.bz2|*.tbz` support.

**Known non-fatal gaps:** LazyVim treesitter parser builds fail on host (bundled tree-sitter CLI needs GLIBC 2.39);
LazyVim falls back to prebuilt parsers on first interactive open. Several tools (eza, gh-dash, sd, git-branchless, spr)
re-install on every run because their `--version` output doesn't match the fetcher's semver regex — harmless.

## 2026-04-21 — Observability phase (branch: power-tui)

Comprehensive observability substrate landed on branch `power-tui` per
`docs/superpowers/specs/2026-04-19-observability-design.md` +
`docs/superpowers/plans/2026-04-19-observability.md`. Execution log at
`docs/superpowers/logs/2026-04-21-observability-execution.md`.

**New scripts:**
- `bin/sysstat.sh` — unified tmux status segment (CPU%/MEM/DISK/GPU/load)
- `bin/nvidia-daemon.sh` — background GPU telemetry writer
- `bin/tmux-save-copilot-sessions`, `bin/tmux-copilot-restore` — Copilot resurrect pair (parity with Claude)
- `bin/wt` — worktree orchestrator for `~/lin_code/` (add/ls/jump/prune/claude/copilot/stack/submit/sl, work-only enforcement)
- `bin/session-end-autocommit.sh` — Claude/Copilot SessionEnd hook (LFS detection + secret-pattern abort, commit-only, no push, no Co-Authored-By)
- `bin/copilot-with-autocommit` — Copilot launcher wrapper with `trap EXIT` session-end hook
- `bin/state-snapshot.sh` — hourly state-repo snapshot (asymmetric-age encryption, LFS, secret-abort)
- `bin/pane-log-toggle.sh` / `bin/pane-log-mode.sh` — per-pane and global tmux logging controls
- `bin/lfs-template-apply`, `bin/lint-shell.sh`

**New systemd units:** `nvidia-daemon.service`, `state-snapshot.service` + `state-snapshot.timer` (hourly, Persistent).

**New configs:** `config/gitattributes-lfs-template`, `config/logrotate/tmux-logs`, `config/copilot/statusline-settings.json`, `git/gitconfig-personal`, `git/gitconfig-work.example`, `shell/zshrc.d/95-pane-log.zsh`.

**tmux config changes:** sysstat segment replaces host-health; `status-interval 5`; `set-clipboard on`; copilot resurrect-processes entry; wt keybindings (`prefix+w/W/C-c/C-p`); pane-logging keybindings (`prefix+L`, `prefix+M-L`).

**Claude Code config:** `SessionEnd` hook added.

**Two-identity git config:** `includeIf` swaps `~/.gitconfig-personal` for `~/my_stuff/` and `~/.gitconfig-work` for `~/lin_code/`.

**Retired:** `bin/host-health.sh` (superseded by `sysstat.sh`).

**Design decisions captured during execution:**
- `age -p` requires `/dev/tty`, so state-snapshot encryption pivoted from symmetric passphrase to **asymmetric age** using an identity file at `~/.config/age/state-identity.txt` (mode 600, gitignored). Decryption: `age -d -i ~/.config/age/state-identity.txt <file>.age`.
- Per-repo `git lfs install` is NOT required — both the session-end hook and state-snapshot detect binaries at commit time and run `git lfs track "*.<ext>"` on demand. Install the `git-lfs` binary once per host (tdnf).
- All auto-commits stay LOCAL; the user pushes manually to prevent half-baked work reaching PR-linked branches.
- MEM colorize in `sysstat.sh` uses used% thresholds (75/90) rather than the plan's inverted `100 - used%` trick — the inversion painted RED at 3% used.

**Test infra:** bats-core + shellcheck (static binary to `~/.local/bin/` — AzL3 tdnf doesn't ship shellcheck). `bin/lint-shell.sh` wraps shellcheck over `bin/` and `tests/`. ~20 new bats tests across sysstat, lfs-template-apply, session-end-autocommit, wt-core, tmux-save-copilot, state-snapshot.

## 2026-04-19 — Host-health status segment

Added `bin/host-health.sh` and a managed block in `tmux/tmux.conf.local.tpl`
that appends it to status-right as a `#(...)` segment re-executed every
`status-interval`. Shows 1-min load and MemAvailable with color escalation
(gray / yellow / red) so runaway load or memory pressure is visible long
before the host wedges. Prompted by a memory crisis on a 54 GB no-swap host
where a parallel `kubectl get pods -A` fan-out across ~12 prod clusters
pushed load past 200 and wedged new sshd connections — an early-warning
status segment would have caught it at load ~15.

**Why not `@loadavg`**: oh-my-tmux already runs its own loop that overwrites
`@loadavg` with just the raw 1-min number every 10s. Fighting for that
variable is fragile (the loop respawns on every tmux reload). Appending a
separate `#(...)` segment lets tmux itself drive re-execution via
`status-interval`, with no background updater process needed.

**Thresholds** (in `bin/host-health.sh`, tune per host):
- YELLOW: load > 10 or MemAvailable < 4G
- RED:    load > 30 or MemAvailable < 1G

Wired through `install.sh` (auto-linked from `bin/`) and `sync.sh`
(`BIN_SCRIPTS`).

## 2026-03-05 — Initial Setup & Fixes

### tmux.conf — Rewrote from scratch

**Original state:**
- Duplicate `tmux-resurrect` plugin declaration
- Broken `if-shell` for resurrect main (`if-shell "test -f ~/.tmux/.tmux-resurrect-main" "run-shell 'tmux-resurrect'"`)
- `default-command` unset — caused restored panes to spawn non-login shells
- No mouse support, no pane navigation bindings, no status bar styling
- `escape-time` not set (500ms default caused input lag)

**Issues encountered:**

1. **"nobody" user in resurrected tmux panes**
   - **Root cause:** `default-command` was empty. tmux-resurrect creates panes using `default-command`, and an empty value spawns bare `/bin/bash` (non-login shell). Non-login shells skip `/etc/profile` and `~/.bash_profile`, so `USER`, `LOGNAME`, and other identity variables were missing.
   - **Fix:** Set `default-command` to `exec /bin/bash --login` so every pane gets a full login shell with proper identity.

2. **Tilde (`~`) paths escaped by tmux in plugin options**
   - **Root cause:** tmux stores `~/bin/...` as `\~/bin/...` in options. The resurrect hook used `eval` which could handle the escaping inconsistently.
   - **Fix:** Changed all paths in `@resurrect-processes` and `@resurrect-hook-post-save-all` to absolute paths (`$HOME/bin/...`).

3. **Claude sessions not persisting across VM restarts**
   - **Root cause:** tmux-resurrect can restore process commands, but `claude` needs `--resume <session_id>` to restore the exact conversation, not just relaunch.
   - **Fix:** Created a two-part system:
     - `tmux-save-claude-sessions` (post-save hook): scans all panes for running `claude` processes, maps each to its Claude Code session ID via the `~/.claude/projects/` directory structure, saves the mapping.
     - `tmux-claude-restore` (inline restore strategy): on restore, looks up the saved session ID for the pane's working directory and runs `claude --resume <id>`, falling back to `claude --continue`.

4. **Save hook failed when resurrect directory didn't exist**
   - **Root cause:** First-time save before any resurrect save had run — `~/.tmux/resurrect/` didn't exist yet.
   - **Fix:** Added `mkdir -p` before writing the session map file.

5. **`pgrep -f '^claude'` was fragile**
   - **Root cause:** `-f` matches against full command line with regex, which could false-match other processes.
   - **Fix:** Changed to `pgrep -x claude` for exact process name matching.

6. **Pipeline subshell swallowed errors in save hook**
   - **Root cause:** `tmux list-panes | while read` runs the loop in a subshell; failures inside are silently lost.
   - **Fix:** Changed to process substitution (`while read ... done < <(tmux list-panes ...)`) so errors propagate to the parent shell.

7. **Claude "nested session" error on restore**
   - **Root cause:** When tmux-resurrect restores a pane that was running claude, the `CLAUDE_CODE_SESSION` environment variable from the original session persists, causing claude to refuse to start.
   - **Fix:** Added `unset CLAUDE_CODE_SESSION` in the restore script before launching claude.

8. **Restore script directory matching was fragile**
   - **Root cause:** `grep " ${DIR} "` could partial-match directories (e.g., `$HOME` matching `$HOME/project`).
   - **Fix:** Changed to `awk '$2 == dir'` for exact field-level matching.

### systemd/tmux.service — New

**Issues:**

9. **tmux not auto-starting after VM restart**
   - **Fix:** Created a systemd user service to auto-start a tmux `main` session on boot.

10. **Systemd service started tmux without login environment**
    - **Root cause:** Systemd user services run in a minimal environment without `USER`, `LOGNAME`, etc.
    - **Fix:** Explicitly set identity environment variables and launch tmux via `bash --login -c '...'`.

### keepalive.sh — New

- Simple daemon that runs `ps` every 5 minutes to keep the VM session alive.
- Runs via `nohup` in background.

## 2026-03-05 — Migrated to oh-my-tmux

### tmux.conf.local — Replaced standalone tmux.conf

**What changed:**
- Standalone `tmux.conf` replaced with oh-my-tmux framework + `.tmux.conf.local` overrides
- `~/.tmux.conf` is now a symlink to `~/oh-my-tmux/.tmux.conf` (upstream, not edited)
- All customizations live in `~/.tmux.conf.local` (survives upstream updates)

**What oh-my-tmux adds:**
- Powerline status bar with built-in variables (hostname, username, uptime, battery, load)
- Nested tmux support (local/remote prefix toggle)
- Auto clipboard detection (xclip/xsel/wl-copy)
- 24-bit color auto-detection
- Built-in TPM integration (no separate `run '~/.tmux/plugins/tpm/tpm'` needed)
- Config edit (`prefix + e`) and reload (`prefix + r`) bindings

**Theme:** Catppuccin Mocha with powerline separators

**Custom status bar variables:**
- `#{loadavg}` — system load average from /proc/loadavg
- `#{gpu_util}` — NVIDIA GPU utilization via nvidia-smi

**Preserved from previous setup:**
- `C-space` prefix
- Vi mode + copy bindings
- `|`/`-` pane splitting with `#!important` to prevent oh-my-tmux override
- `h/j/k/l` pane navigation with `#!important`
- Login shell (`default-command "exec /bin/bash --login"`)
- All resurrect/continuum persistence settings
- Claude Code session save/restore hooks
- Systemd auto-start service

**Issues encountered during migration:**

11. **Custom functions parsed as tmux commands**
    - **Root cause:** oh-my-tmux custom functions must be inside the `# EOF` comment block with `# ` prefix on every line. Functions were written as raw shell code, which tmux tried to parse.
    - **Fix:** Added `# ` prefix to all function lines per oh-my-tmux convention.

12. **tmux-sensible plugin removed**
    - oh-my-tmux includes equivalent defaults built-in, so tmux-sensible was redundant and removed from plugin list.

## 2026-03-05 — Claude Code Power-User Config

- Agent teams enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`)
- Extended thinking always on (`alwaysThinkingEnabled`)
- Auto-memory enabled for persistent learning
- Max output tokens 64k, autocompact at 80%
- Expanded permission allowlist (45+ commands auto-allowed)
- Custom agents: `security-reviewer` (opus), `perf-profiler` (sonnet), `researcher` (opus)
- Power-user statusline: model, git branch, GPU util+VRAM, load, cost, context bar
- Branch protection hook (PreToolUse blocks Edit/Write on main/master)
- Shell aliases: `c`, `cc`, `cr`, `cw` for claude shortcuts
- Notification hook via tmux display-message
- Global CLAUDE.md with environment, workflow, Python style rules

## 2026-03-05 — Tmux 3.5a Upgrade & Reproducibility

### Issues encountered:

13. **Cmd+click links not working in tmux**
    - **Root cause:** tmux 3.2a lacks OSC 8 hyperlink passthrough (`allow-passthrough` added in 3.3, `hyperlinks` terminal feature in 3.4).
    - **Fix:** Built tmux 3.5a from source to `~/.local/bin/tmux`. Added `set -g allow-passthrough on` and `set -as terminal-features ",*:hyperlinks"` to config.

14. **prefix+p/n broken for previous/next window**
    - **Root cause:** oh-my-tmux rebinds `prefix+p` to `paste-buffer`.
    - **Fix:** Added `bind p previous-window #!important` and `bind n next-window #!important`.

15. **Claude Code keybinding error (ctrl+t conflict)**
    - **Root cause:** `ctrl+t` conflicts with a Claude Code internal binding.
    - **Fix:** Removed `ctrl+t` from keybindings.json.

16. **Pane contents restore crashes sessions on tmux version upgrade**
    - **Root cause:** tmux-resurrect's `pane_contents.tar.gz` saved by 3.2a is incompatible with 3.5a restore.
    - **Fix:** Run restore with `@resurrect-capture-pane-contents off`. Re-enable after first successful save under 3.5a.

17. **Claude "nested session" error — incomplete env var cleanup**
    - **Root cause:** `tmux-claude-restore` only unset `CLAUDE_CODE_SESSION` but `CLAUDE_CODE_ENTRY_POINT` and `CLAUDECODE` also leak into restored panes.
    - **Fix:** Unset all three variables before launching claude.

18. **Systemd service hardcoded paths and username**
    - **Root cause:** Static service file had `/bin/tmux` and `USER=<user>` baked in.
    - **Fix:** Replaced with `tmux.service.tpl` template. `install.sh` generates actual service via sed with `$(whoami)` and `$HOME`.

19. **Resurrect restore spinner stuck in status bar**
    - **Root cause:** Orphaned `tmux_spinner.sh` process from failed pane-contents restore.
    - **Fix:** Kill the spinner process (`pkill -f tmux_spinner`), clear with `tmux display-message ''`.

20. **Continuum auto-restore didn't fire on new tmux server**
    - **Root cause:** Continuum checks on first client attach, but the new server had a `main` session (not matching any saved session names).
    - **Fix:** Manual restore via `tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh` after killing the default `main` session.
