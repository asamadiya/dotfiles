# Changelog

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
