# Observability — User Guide

This guide covers the observability surfaces and workflows added by the
`power-tui` branch. For the design rationale, see
[the observability spec](../superpowers/specs/2026-04-19-observability-design.md).
For task-by-task history see the
[execution log](../superpowers/logs/2026-04-21-observability-execution.md).

---

## One-time host setup (run manually, then forget)

Install these once per host (none run automatically — all require sudo or
elevated actions the dotfiles install.sh doesn't perform on your behalf):

```bash
sudo tdnf install -y git-lfs bats

# shellcheck: AzL3 tdnf doesn't ship it — use the static binary:
mkdir -p ~/.local/bin && cd /tmp
curl -sSL -o sc.tar.xz https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz
tar xJf sc.tar.xz && mv shellcheck-v0.10.0/shellcheck ~/.local/bin/ && chmod +x ~/.local/bin/shellcheck
rm -rf sc.tar.xz shellcheck-v0.10.0

# age (Filo Sottile) — static binary:
cd /tmp && curl -sSL -o age.tar.gz https://github.com/FiloSottile/age/releases/download/v1.2.0/age-v1.2.0-linux-amd64.tar.gz
tar xzf age.tar.gz && mv age/age age/age-keygen ~/.local/bin/ && chmod +x ~/.local/bin/{age,age-keygen}
rm -rf age age.tar.gz

# Generate the age identity used by state-snapshot (one-time):
mkdir -p ~/.config/age
age-keygen -o ~/.config/age/state-identity.txt
chmod 600 ~/.config/age/state-identity.txt

# Create the work dir if it doesn't exist:
mkdir -p ~/lin_code

# Initialize the work-side state repo:
cd ~/lin_code && git init state && cd state
git remote add origin <your-private-state-repo-url>   # optional — auto-commits stay local anyway
```

Then run `./install.sh` in the dotfiles repo once to wire symlinks, systemd
units, and the state-snapshot timer.

---

## Keybindings cheatsheet

### tmux (prefix: Ctrl-Space)

| Key | Action |
|---|---|
| `prefix+C-w` | Fuzzy-jump to any existing worktree under `~/lin_code/wt/` |
| `prefix+W` | Prompt for branch, create new worktree + tmux window |
| `prefix+C-c` | Prompt for branch, create worktree + launch Claude Code (YOLO) |
| `prefix+C-p` | Prompt for branch, create worktree + launch Copilot CLI (YOLO) |
| `prefix+L` | Toggle pane logging (mode A — per-pane, on-demand) |
| `prefix+M-L` | Toggle pane-logging mode B globally (auto-on shell, auto-off TUI) |
| `prefix+f` | Fuzzy pick session/window/pane (tmux-fzf) |
| `prefix+F` | tmux-fingers pattern hints (URLs, hashes) |
| `prefix+[` | Enter copy-mode (vi bindings: `v` start, `V` line, `y` yank) |
| `prefix+C-s` / `prefix+C-r` | Manual resurrect save / restore |
| `prefix+I` | Install tpm plugins |
| `prefix+m` | Toggle mouse |
| `prefix+g` | (after productivity phase installs lazygit) open lazygit popup |

Mouse (unchanged from prior config): click-to-focus-pane,
drag-border-to-resize, wheel-to-scrollback, drag-to-select-and-copy
(auto via xclip + OSC 52), Shift+drag for native terminal select.

### zsh (after the productivity phase installs it)

| Key | Action |
|---|---|
| `Ctrl-R` | atuin interactive history (filter by cwd/exit/host) |
| `Up arrow` | linear per-session history (atuin's Up-rewire stays off) |

---

## Daily workflows

### Start parallel work on three features simultaneously

1. `cd ~/lin_code/<repo>`
2. `prefix+C-c`, branch `feature-one` → tmux window `<repo>/feature-one` with Claude YOLO.
3. `prefix+C-c`, branch `feature-two` → another window with Claude YOLO.
4. `prefix+C-p`, branch `feature-three` → Copilot YOLO window.
5. Switch windows with `prefix+<N>` or `prefix+C-w` (fzf).
6. Each worktree is at `~/lin_code/wt/<repo>/feature-N/`. Isolated.

### End a session

Exit Claude (`/exit`) or Copilot (`exit`). The session-end hook fires:
- Runs in the worktree.
- Detects binaries; auto-`git lfs track`s their extensions.
- Aborts loudly on recognised secret patterns (`ghp_`, `gho_`, `github_pat_`, `sk-…`, `AKIA…`).
- Otherwise: `git add -A && git commit -m "session <agent> <short-id>: +X -Y"`.
- **Does not push.** You push manually when ready.

### Recover after a VM crash or reboot

1. VM restarts. `systemd --user tmux.service` autostarts tmux.
2. tmux-continuum auto-restores the last saved session.
3. Each resurrected Claude pane runs `claude --resume=<id> --dangerously-skip-permissions`.
4. Each resurrected Copilot pane runs `copilot --resume=<id> --allow-all-tools`.
5. Windows keep their `<repo>/<branch>` names — you know which worktree is which.
6. If something breaks: `tmux kill-server && systemctl --user restart tmux`.

### Search across past pane output

```bash
rg 'OOM' ~/logs/tmux/
rg --files-with-matches 'curl.*/api/v2' ~/logs/tmux/2026/04/
```

Pane logs only exist for panes where logging was on:
- Mode A (`prefix+L`) turned it on manually for specific panes, or
- Mode B (`prefix+M-L`) is enabled AND the pane is in a shell (not nvim/claude/copilot/htop/…).

### Browse your own shell history

`Ctrl-R` → atuin (after productivity phase). Filter keys:
- `Tab` — cycle filter mode (session / cwd / host / global)
- Type to filter
- `Enter` runs, `Tab` places on prompt for editing.

### Inspect the state repo

```bash
cd ~/lin_code/state
git log --oneline | head
ls claude/projects/          # Claude sessions (cleartext)
ls copilot/session-state/    # Copilot sessions (cleartext)
ls recordings/               # asciinema .cast files (LFS)
ls snapshots/<hostname>/     # host inventory
ls atuin/                    # history.db.age (encrypted)
ls logs/                     # *.tar.gz.age (encrypted daily rollups)
```

### Decrypt something from the state repo

```bash
# atuin history:
age -d -i ~/.config/age/state-identity.txt ~/lin_code/state/atuin/history.db.age > /tmp/history.db
sqlite3 /tmp/history.db 'SELECT command FROM history ORDER BY timestamp DESC LIMIT 20;'

# Daily log rollup:
age -d -i ~/.config/age/state-identity.txt ~/lin_code/state/logs/2026-04-21.tar.gz.age | tar tz
```

### Push the state repo (manually, when you want)

```bash
cd ~/lin_code/state
git log origin/master..HEAD        # see what would go out
git diff origin/master..HEAD       # review
git push origin master
```

Never automated — intentional, to protect PR-linked branches from half-baked
auto-commits.

---

## Commands reference

### `wt`

```
wt add <branch>                  Create worktree at ~/lin_code/wt/<repo>/<branch>/ + tmux window
wt ls                            List all worktrees with branch, dirty flag, last commit
wt jump                          fzf-pick a worktree, select that tmux window
wt prune                         Interactive removal of merged worktrees
wt claude <branch> [--record]    Add worktree + launch Claude YOLO (optional asciinema record)
wt copilot <branch> [--record]   Add worktree + launch Copilot YOLO
wt stack <base-branch>           Add a stacked worktree, spr track (if installed)
wt submit                        spr diff → push stacked PRs (requires spr installed)
wt sl                            git-branchless stacked log (fallback: git log --graph)
```

Scope rule: `wt` refuses to run unless cwd is under `~/lin_code/`. `~/my_stuff/`
stays as a normal single-checkout dir — work on feature branches like
`power-tui` directly.

### `sysstat.sh`

Runs as a tmux `#(...)` segment every 5 s. Manually:

```bash
bin/sysstat.sh
```

GPU segment only appears when `/tmp/nvidia-stats` is fresh (<30 s old),
written by `nvidia-daemon.service`.

### `nvidia-daemon.sh`

Background systemd `--user` service. Installed (via `install.sh`) only when
`/proc/driver/nvidia` exists. On no-GPU hosts, exits cleanly with the message
`nvidia-daemon: NVIDIA driver not present; exiting cleanly`.

```bash
systemctl --user status nvidia-daemon   # check
systemctl --user restart nvidia-daemon  # if you just installed the driver
```

### `state-snapshot.sh`

Hourly systemd timer (`systemctl --user list-timers` shows it). Manual run:

```bash
bin/state-snapshot.sh            # commit new state in ~/lin_code/state/
STATE_REPO=/other bin/state-snapshot.sh   # alternate destination
```

Commit-only, never pushes.

### `session-end-autocommit.sh`

Called automatically at Claude/Copilot session end. Manually:

```bash
bin/session-end-autocommit.sh claude <session-id>
```

No push. No pre-commit invocation.

### `pane-log-toggle.sh` / `pane-log-mode.sh`

Bound to `prefix+L` and `prefix+M-L`. Manual (inside a tmux pane):

```bash
bin/pane-log-toggle.sh   # flip current pane
bin/pane-log-mode.sh     # flip mode B sentinel globally
```

Log files: `~/logs/tmux/YYYY/MM/DD/S-<sess>_W-<win>_P-<pane>.log`.

### `lfs-template-apply`

Drops the shared `.gitattributes` LFS pattern list into any target repo
(idempotent — appends only missing patterns).

```bash
bin/lfs-template-apply ~/lin_code/state
bin/lfs-template-apply ~/some-other/repo
```

### `lint-shell.sh`

Runs `shellcheck` over every `*.sh` / `*.bash` under `bin/` and `tests/`.
Returns non-zero on any failure. Used by CI (if added later) and as a
post-edit smoke test.

```bash
bin/lint-shell.sh
```

---

## Troubleshooting

### "pane-border-status keeps overlapping my content"

It shouldn't — `pane-border-status` is intentionally **off** in this design.
Check with `tmux show -g pane-border-status`; if it's on, run
`tmux set -g pane-border-status off` and reload the config.

### "sysstat segment shows CPU 0% forever"

Reset the rolling state file and wait one interval:

```bash
rm /tmp/sysstat.cpu.state
```

The first call only primes the sample; the second call (5 s later) computes
the delta.

### "Copilot resurrect relaunches but the session thinks it's active elsewhere"

Stale-lock cleanup didn't fire. Nuke and relaunch manually:

```bash
rm -f ~/.copilot/session-state/*/inuse.*.lock
tmux send-keys -t <pane> C-c 'copilot --resume=<uuid> --allow-all-tools' Enter
```

Root cause: VM crashed while the copilot lock was open; lock's PID reference
is stale. The restore script clears locks >30 s old automatically — this
failure mode is unusual.

### "Auto-commit aborted with secret-pattern error"

A file in the working tree matches the secret regex. Commit was aborted; the
working tree is intact. Inspect:

```bash
grep -rE '(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA)' .
```

Remove or redact, then commit manually (`git add …; git commit -m …`) or let
the next session-end fire cleanly.

### "state-snapshot.timer shows inactive"

```bash
systemctl --user status state-snapshot.timer
systemctl --user start state-snapshot.timer
journalctl --user -u state-snapshot.service
```

Most common cause: missing `~/.config/age/state-identity.txt`. The script
exits 0 silently when the identity is missing, so the service flips to
success without actually doing anything. Run the one-time setup
(`age-keygen -o ~/.config/age/state-identity.txt`).

### "I want to disable auto-commit entirely for a session"

Not yet wired — this is a known gap. Workaround: exit Claude/Copilot with no
changes in the working tree. The hook sees a clean tree and exits 0
silently.

A future refinement (not in this phase) could add `NO_AUTOCOMMIT=1` as an
env gate at the top of `bin/session-end-autocommit.sh`.

### "gh-dash keeps saying I'm not authenticated"

`gh-dash` only runs in the work context (`~/lin_code/*`). Confirm:

```bash
cd ~/lin_code/<any-work-repo>
gh auth status
```

If personal (`~/my_stuff/*`): gh-dash is intentionally NOT authenticated
there (PAT-only workflow for personal repos — see the dotfiles memory on
two-identity authoring).

### "Git identity got mixed up on a commit"

Check the `includeIf` resolution:

```bash
cd ~/my_stuff/<repo> && git config --show-origin user.email   # expect asamadiya@users.noreply.github.com
cd ~/lin_code/<repo> && git config --show-origin user.email   # expect work email
```

If wrong, ensure `~/.gitconfig` is symlinked to `dotfiles/git/gitconfig`
(install.sh does this) and `~/.gitconfig-personal` and `~/.gitconfig-work`
both exist. `~/.gitconfig-work` is per-host — copy from
`dotfiles/git/gitconfig-work.example` and fill in your real LinkedIn email.

---

## Before-you-push checklist

Because auto-commit is always LOCAL, you control what leaves the machine.
Before `git push` on any work repo:

1. `git log origin/<branch>..HEAD` — inspect the commit sequence.
2. `git diff origin/<branch>..HEAD` — review the diff.
3. `grep -rE '(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA|password|secret)' <changed files>`
   — quick self-audit even though auto-commit already screens.
4. `git log --author=asamadiya` — confirm no identity mixing in personal
   repos. For work, confirm your LinkedIn email is the author.

---

## Disaster recovery

### State repo — lost `~/.config/age/state-identity.txt`

The identity file is the only thing that can decrypt the `*.age` files in the
state repo. Guard it: back it up off-host the day you generate it (e.g.
copy to a password manager's secure-note field; it's a short file).

If lost on all hosts simultaneously, the encrypted buckets (atuin DB export,
tmux log rollups) are unrecoverable **by design**. Cleartext buckets (Claude
session JSONL, Copilot session-state, tmux-resurrect dumps, host snapshots)
are unaffected.

### Worktree lost after a `git worktree remove --force`

Check the main repo's reflog and re-create:

```bash
cd ~/lin_code/<repo>
git reflog <branch>
git checkout -b <branch>-rescue <sha>
wt add <branch>-rescue
```

Worktree files are gone, but the commit history on the branch is intact.

### Auto-committed the wrong thing

Nothing is pushed, so:

```bash
cd <worktree>
git log -1                 # see the hook's commit
git reset --soft HEAD~1    # un-commit, keep working tree
# edit as you like
git commit ...             # commit manually when ready, or let the next
                           # session-end hook fire
```

### VM-wide restart during a session

1. Let the VM come back.
2. `systemd --user tmux.service` auto-starts tmux.
3. tmux-continuum triggers resurrect.
4. Claude / Copilot panes come back resumed.
5. Claude Code resumes the exact conversation from `~/.claude/sessions/<uuid>.jsonl`.
6. Copilot CLI resumes from `~/.copilot/session-state/<uuid>/events.jsonl`.
7. If state was snapshotted to `~/lin_code/state/` before the crash, decrypt
   atuin history and tmux log rollups via `age -d -i`.

---

## Cross-reference

- **Spec:** `docs/superpowers/specs/2026-04-19-observability-design.md`
- **Plan:** `docs/superpowers/plans/2026-04-19-observability.md`
- **Execution log:** `docs/superpowers/logs/2026-04-21-observability-execution.md`
- **Top-level README:** `README.md` (Observability section)
- **CLAUDE.md:** `CLAUDE.md` (Key Scripts table)
- **Changelog:** `CHANGELOG.md` (dated block for this phase)
