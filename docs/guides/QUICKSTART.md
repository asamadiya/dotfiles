# Quickstart — a 30-minute tour of the power-tui setup

For someone comfortable with **vim** and **tmux** but new to zsh, the modern
CLI stack, and the observability surfaces that the `power-tui` and
`power-productivity` phases landed.

Read top-to-bottom once; each section ends with a **"try this"** command so
you build muscle memory as you go. Skip anything you already know.

For deep-dive reference, see:
- [Observability user guide](./2026-04-19-observability-user-guide.md) — tmux status + session continuity + state repo.
- [Productivity user guide](./2026-04-21-productivity-user-guide.md) — shell + CLI tools + nvim.

---

## 0. Before you begin — make sure you're in a zsh pane

The tmux shell swap means **new** panes are zsh. Panes created before the
swap are still the old bash.

Try this: open a brand-new tmux window (`prefix+c` where prefix = `Ctrl-Space`).

What you should see:
- A **two-line prompt** with a cwd + git branch on line 1 and a `❯` on line 2 (that's starship).
- If you start typing a command and pause, a **greyed-out suggestion** appears (that's `zsh-autosuggestions` — accept with `→` or `Ctrl-F`).
- As you type `ls `, the text turns **green/red** depending on validity (that's `fast-syntax-highlighting`).

Check:
```
echo "$SHELL"              # /home/spopuri/.local/bin/zsh
ps -p $$ -o comm=          # zsh
~/.local/bin/zsh --version # zsh 5.8
```

If you see `bash` instead, that tmux pane was spawned before the swap —
open a fresh one.

---

## 1. The status bars — what you're looking at

### tmux status-right (bottom of every tmux pane)

```
CPU 23% · MEM 18G/108G (16%) · DISK 42% · L 1.2
```

Four live metrics every 5 seconds (via `bin/sysstat.sh`). Colors escalate:
gray → yellow (warn) → red/bold (critical). GPU section appears automatically
when the NVIDIA driver is present.

### Starship prompt (in every zsh pane)

```
 ~/my_stuff/dotfiles  main [+*]
❯
```

That's cwd + branch + dirty glyphs (`+` staged, `*` modified, `?` untracked).
The `❯` turns red on the next prompt if your last command exited non-zero.

### Claude Code statusline (bottom of Claude UI)

```
Opus power-tui* dotfiles L:1.2 $0.10 █████░░░░░ 53%
```

Model · branch+dirty · dir · load · cost · context bar.

### Copilot CLI statusline (when running copilot)

```
project · branch clean|dirty │ ctx ████ 42% │ req 7 │ dur 3m
```

**The rule:** git state lives in the prompt + AI statuslines. tmux status is
machine-only (no git). No duplication across surfaces.

**Try this:** `stress-ng --cpu 4 --timeout 8s &` — watch the tmux status CPU%
jump to yellow/red, then settle.

---

## 2. Shell superpowers — the things you'll use every minute

### `Ctrl-R` — atuin history picker

Not your grandma's `Ctrl-R`. This one is a full TUI:
- Fuzzy-type to filter
- `Tab` toggles filter mode (session / cwd / host / global)
- Shows exit code + duration + timestamp per match

Cloud-sync means history pasted on ld4 shows up on ld5 automatically. One-time
setup:
```
atuin register -u <username> -e <email>   # FIRST host only
atuin login -u <username>                  # every other host
atuin sync
```

### `z <dir>` — smart `cd` (zoxide)

Types anywhere. It remembers places you've been.
```
z dotfiles            # jumps to wherever "dotfiles" scored highest
zi                    # interactive fzf picker over all known paths
```

### `Ctrl-T` — fzf file picker

Pipes fd into fzf. Anywhere you're typing a command, hit `Ctrl-T` to fuzzy-pick
a file path from cwd and inject it on the command line.
```
vim <Ctrl-T>          # fuzzy-select a file to edit
cp <Ctrl-T> /tmp/     # pick a file, copy to /tmp/
```

### `Alt-C` — fzf cd

Same but for directories.

### Tab completion with carapace

Tab after any modern CLI tool (`kubectl get po`, `git switch`, `gh pr create`)
cycles through completions — not just file paths, but flag names, sub-commands,
enum values. If you don't see what you expect, carapace may not have loaded
yet (it defers to first prompt); try pressing `Enter` on an empty line and
tabbing again.

**Try this:**
1. `z dotfiles` → you're in `~/my_stuff/dotfiles`.
2. `Ctrl-T README` → fuzzy-pick `README.md`, it lands on the command line.
3. Prefix with `bat -p`, hit Enter → syntax-highlighted readme.

---

## 3. Modern CLI — overrides you won't notice until you do

These aliases are set; the original commands are still reachable with `\ls`,
`\cat`, etc.:

| Typed | Runs | Win over default |
|---|---|---|
| `ls` | `eza --icons` | Git column, icons, cleaner columns |
| `ll` | `eza -lah --icons --git` | Your everyday "show me everything" |
| `lt` | `eza --tree --level=2 --icons` | Quick tree view without `find`-wrestling |
| `cat` | `bat -p` | Syntax highlight, preserves pipeable behavior |

Not aliased (type these explicitly — it's the habit that matters):

| Command | Does what |
|---|---|
| `rg <pat>` | Ripgrep — gitignore-aware, parallel grep. Dominates `grep -r`. |
| `fd <pat>` | Sane `find`. `fd '\.py$'` finds all Python files. |
| `bat <file>` | Same as `cat` alias but with a pager. Good for long files. |
| `sd 'foo' 'bar' file.txt` | Modern `sed` for simple substitution. |
| `pixi init` / `pixi add <pkg>` / `pixi run <task>` | Polyglot project env (conda-forge + lockfile). See productivity guide. |

**Try this:** `rg 'session-end' ~/my_stuff/dotfiles` — gitignore-aware grep
across the repo in milliseconds.

---

## 4. Git workflow — faster than raw git

### `lg` → lazygit (TUI)

The daily driver for any non-trivial git op. `prefix+g` inside tmux opens it
in a popup; or type `lg` at the prompt.

Inside lazygit:
- `space` — stage/unstage hunk or file
- `a` — stage all
- `c` — commit (opens your `$EDITOR`)
- `P` — push
- `p` — pull
- `r` — rebase interactive
- `z` — undo last action
- `?` — help (full keymap)

### `gst`, `gd`, `glg`, `gfix`

Shortcuts for the bash-free moments:
- `gst` — `git status`
- `gd` — `git diff`
- `glg` — graph log of all branches, one-line, decorated
- `gfix` — `git absorb --and-rebase` — staged hunks auto-fixup onto the right
  commits. Magic for review-driven workflows.

### `delta` + `difft`

All `git diff` / `git log -p` output pipes through **delta** automatically
(syntax-highlighted side-by-side if terminal is wide enough). For semantic
diffs across refactors:
```
gdft HEAD~5..HEAD     # alias: GIT_EXTERNAL_DIFF=difft git log -p --ext-diff
```

Difftastic shows **moved functions** and **renamed vars** as structural
changes, not line soup.

### Stacked PRs via `spr` + local nav via `git-branchless`

For work repos (under `~/lin_code/`):
- `wt stack <base-branch>` — create a stacked worktree.
- `wt submit` — `spr diff` pushes the whole stack, creates/updates GitHub PRs.
- `wt sl` — `git sl` (branchless stacked log, visual DAG of your active work).

**Try this:** in this very repo: `lg` → arrow-key around the commit list on
the right → press `space` on a hunk → `c` to commit → `<esc>` back out.
(Read-only exploration — press `<esc>`/`q` without committing if you just
want to see the UI.)

---

## 5. AI agents — Claude + Copilot with worktree isolation

### The `wt` worktree orchestrator

Only works under `~/lin_code/` (safety rail). Key subcommands:

```
wt add feature-foo              # create worktree + tmux window
wt ls                           # list all worktrees w/ branch + dirty state
wt jump                         # fzf-pick, switch to that tmux window
wt claude feature-bar           # worktree + tmux window + claude YOLO
wt copilot feature-baz          # worktree + tmux window + copilot YOLO
wt prune                        # interactive cleanup of merged worktrees
```

The agents launch with permissions-bypass flags by default (YOLO):
- `claude --dangerously-skip-permissions`
- `copilot --allow-all-tools`

Safe because every session end **auto-commits** the working tree locally
(see §6).

### tmux bindings (prefix = `Ctrl-Space`)

| Key | Action |
|---|---|
| `prefix+w` | tmux default tree picker (sessions/windows/panes) |
| `prefix+C-w` | `wt jump` fzf popup |
| `prefix+W` | prompt for branch → `wt add` |
| `prefix+C-c` | prompt for branch → `wt claude` |
| `prefix+C-p` | prompt for branch → `wt copilot` |

### Parallel agents

Nothing stops you from having **five claude sessions** on five branches in
five tmux windows at once. Each worktree is isolated; a commit in one
doesn't touch the others.

**Try this (read-only):** `wt ls` — should print nothing (no worktrees yet),
exit cleanly.

---

## 6. Observability — the 1000 eyes

### Session resurrect (tmux-resurrect + continuum)

Auto-saves every 5 min. tmux auto-starts on boot via `systemd --user
tmux.service`, then continuum restores your session. Claude and Copilot
panes come back with **the same session IDs** — they resume the exact
conversation, not a fresh one.

No action needed; it just works. To manually save: `prefix+C-s`. Restore:
`prefix+C-r`.

### Session-end auto-commit

Every time Claude or Copilot exits, a hook fires:
- Detects binary files → auto-`git lfs track` the extensions.
- Aborts on known secret patterns (`ghp_`, `gho_`, `github_pat_`, `sk-…`, `AKIA…`).
- Otherwise: `git add -A && git commit -m "session <agent> <sid>: +X -Y"`.
- **Never pushes.** You push manually when ready.

Check: after an agent session, `git log -1` shows the new commit.

### State repo — `~/lin_code/state/`

Hourly systemd timer (`state-snapshot.timer`) commits a snapshot:
- `claude/projects/` — your Claude sessions
- `copilot/session-state/` — your Copilot sessions
- `atuin/history.db.age` — encrypted shell history (via asymmetric age)
- `tmux/resurrect/` — layout dumps
- `logs/*.tar.gz.age` — encrypted pane-log rollups
- `snapshots/<hostname>/inventory.txt` — lscpu, lstopo, df, lspci, …

All local; never pushed. You `git push` when ready. Check:
```
systemctl --user list-timers | grep state-snapshot
cd ~/lin_code/state && git log --oneline | head
```

### Pane logging

Default: **off** (zero cost until you turn it on).

- **`prefix+L`** — toggle logging for the focused pane. Output captured to
  `~/logs/tmux/YYYY/MM/DD/S-*.log`.
- **`prefix+M-L`** — toggle global auto-mode: zsh hook enables logging on
  every shell prompt and disables it during known TUI commands (`vim`,
  `claude`, `htop`, etc.).

Grep later: `rg 'ERROR' ~/logs/tmux/`.

### Decrypt something from the state repo

```
# atuin history (cross-host shell commands):
age -d -i ~/.config/age/state-identity.txt \
  ~/lin_code/state/atuin/history.db.age > /tmp/history.db
sqlite3 /tmp/history.db \
  'SELECT command FROM history ORDER BY timestamp DESC LIMIT 20'

# a daily tmux log rollup:
age -d -i ~/.config/age/state-identity.txt \
  ~/lin_code/state/logs/2026-04-21.tar.gz.age | tar tz
```

**Try this:**
```
systemctl --user list-timers | grep state-snapshot
```
— should show the next firing time for state-snapshot.timer.

---

## 7. Neovim — first steps

Two distros coexist:
- `nvim` → NvChad (default)
- `lv` → LazyVim (alias `NVIM_APPNAME=nvim-lazy nvim`)

Your vim muscle memory works in both. Leader key is `<space>`.

### Cheat sheet (both distros)

| Key | Action |
|---|---|
| `<leader>ff` | Find files (telescope) |
| `<leader>fg` | Live grep in the project |
| `<leader>fb` | Switch buffer |
| `<leader>fk` | Show all keymaps |
| `<leader>gg` | Lazygit popup |
| `<leader>gd` | Git preview current hunk |
| `<leader>gs` | Git blame toggle |
| `<leader>xx` | Trouble diagnostics |
| `<leader>e`  | Oil floating file manager |
| `gd` | LSP definition |
| `gr` | LSP references |
| `K`  | LSP hover docs |

### First open

```
nvim
```
On first launch, NvChad auto-installs plugins (~15-30 seconds). Expect
`Lazy` output. When done, press `q` to close the lazy window.

Python/Rust/Go files auto-trigger **Mason** to install the corresponding LSP
(pyright, rust-analyzer, gopls). First open of a `.py` file may take a
minute; subsequent opens are instant.

**Try this:**
```
nvim README.md
```
Then `<space>ff` to see Telescope, `<esc>` to dismiss, `:q` to exit.

---

## 8. "I want to…" common workflow recipes

### Start three agents on three parallel features

```
cd ~/lin_code/<repo>
prefix+C-c   → feature-auth
prefix+C-c   → feature-billing
prefix+C-p   → feature-cache   (copilot on this one)
```
Three tmux windows, three worktrees, three agents. Switch with `prefix+1`,
`prefix+2`, `prefix+3`.

### Find the command I ran yesterday on ld4

`Ctrl-R` → type fragments → `Tab` to switch to "global" filter → locate,
Enter to run or `Tab` to put on command line for editing.

### Review and push a series of commits

```
gst                    # check status
lg                     # inspect, amend, reorder, squash via TUI
glg                    # graph log
git push               # when ready
```

### See all open PRs I'm involved in (work repos)

```
gh dash               # only works under ~/lin_code/
# or: prefix+d inside tmux (if you bind it)
```

### Figure out what a tool does

```
tldr <tool>           # example-first simplified man page
<tool> --help | head  # full help
```

### Benchmark two commands

```
hyperfine 'python v1.py' 'python v2.py'
```

### "Show me what changed between HEAD and master semantically"

```
gdft master..HEAD     # difftastic, AST-aware
```

### "What's using my disk?"

```
dust ~/                   # interactive tree of disk hogs
dfh                       # duf — prettier df
```

### "What processes are eating memory?"

```
btop                      # full interactive monitor
psh --watch               # procs live
```

### "Record this terminal session for later review"

```
rec /tmp/session.cast     # asciinema rec
# work, then ctrl+D to stop
asciinema play /tmp/session.cast
```

---

## 9. Getting help

### When something is wrong

1. `tldr <cmd>` — quick example-based primer.
2. `<cmd> --help` — most tools have decent help.
3. Check the two deep-dive guides:
   - `docs/guides/2026-04-19-observability-user-guide.md` — troubleshooting for tmux status, state repo, session resurrect.
   - `docs/guides/2026-04-21-productivity-user-guide.md` — troubleshooting for zsh, CLI tools, neovim.
4. Check `CHANGELOG.md` — every documented bug + fix from both phases.

### When the shell feels slow

```
hyperfine -m 10 '~/.local/bin/zsh -ic exit'
~/.local/bin/zsh -ic 'zinit times'
```

Target: cold start < 150 ms. ld5 measures ~55 ms currently.

### "Reset my nvim state"

```
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
nvim --headless "+Lazy! sync" "+qa!"
```
(For LazyVim: replace `nvim` with `nvim-lazy` in each path.)

### "Reinstall a tool from the user-bins table"

```
bin/install-user-bins.sh --force <tool>
```

### "Bump every tool to latest stable"

Edit the pins in `bin/install-user-bins.sh` — resolve each via
`curl -s https://api.github.com/repos/<owner>/<repo>/releases/latest | jq -r .tag_name`
— commit the diff, re-run `bin/install-user-bins.sh`.

---

## 10. What's next

- **ld4 rollout.** Clone dotfiles + `./bin/install-user-bins.sh` + `./install.sh` + `atuin login` + push a session to verify cloud sync.
- **NVIDIA driver + CUDA** — unlocks the GPU segment in the tmux status, plus `nvitop` / `gpustat` / `py-spy --native` for ML workflows.
- **Mac-side dotfiles** — Brewfile, Ghostty/WezTerm, SSH ControlMaster, Maccy clipboard history, shared starship config. Its own spec + plan cycle.
- **Agentic-loop tools** — `aider`, `simonw/llm`, `ollama`. Another spec cycle.
- **Polyglot-env spec** (remaining). `pixi` landed early (see productivity
  guide) but the full cycle — mise / uv coexistence, direnv hook integration,
  LSP-per-project conventions — is still its own spec.

All of those are their own spec→plan→implementation cycles — you decide when
to tackle each one.
