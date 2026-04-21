# Productivity — User Guide

Covers the second-phase power-tui additions: **zsh as the tmux shell, ~35 CLI
tools in `~/.local/bin/`, and two neovim distros** (NvChad default, LazyVim
fallback via `NVIM_APPNAME`).

Design: `docs/superpowers/specs/2026-04-21-productivity-design.md`.
Plan: `docs/superpowers/plans/2026-04-21-productivity.md`.
Execution log: `docs/superpowers/logs/2026-04-21-productivity-execution.md`.

---

## First time on a new host

```bash
cd ~/my_stuff/dotfiles
./bin/install-user-bins.sh        # installs zsh + nvim + ~35 tools (~5 min)
./install.sh                       # symlinks everything into place

# Atuin cloud sync — interactive, run once per host:
atuin register -u <user> -e <email>    # only on the FIRST host ever
atuin login -u <user>                   # on every subsequent host
atuin sync
```

Open a new tmux pane → zsh with the two-line starship prompt. On first open,
zinit bootstraps itself and clones plugins (one-time, ~5 s).

## Shell

- **Interactive shell in tmux:** `zsh` at `~/.local/bin/zsh` (installed via
  `romkatv/zsh-bin`, no sudo). Reports `zsh 5.8` on this host.
- **Shell outside tmux** (SSH direct, cron, scripts): **bash** (unchanged).
- **Config entry:** `~/.zshrc` → `dotfiles/shell/zshrc`; modules under
  `~/.zshrc.d/` (symlink to `dotfiles/shell/zshrc.d/`).
- **Cold start:** measured ~55 ms on ld5 via
  `hyperfine '~/.local/bin/zsh -ic exit'` (target < 150 ms).

### Keystrokes that changed

| Key | Action |
|---|---|
| `Ctrl-R` | **atuin** history picker (cross-host via cloud sync) |
| `Ctrl-T` | fzf file picker (finds from cwd with fd) |
| `Alt-C` | fzf cd (dirs from cwd with fd) |
| `z <dir>` | zoxide frecency-ranked cd |
| `zi` | zoxide interactive fzf picker |
| `Esc` then `v` | open current command in `$EDITOR` (vi mode) |
| `Up arrow` | linear per-session history (atuin up-rewire stays off) |

### Aliases

Claude / Copilot (ported from bash):
- `c` / `cc` / `cr` / `cw` — claude / --continue / --resume / --worktree
- `cp` — copilot

Neovim:
- `nvim` — NvChad
- `lv` — LazyVim (via `NVIM_APPNAME=nvim-lazy nvim`)

Git:
- `lg` — lazygit
- `gst` — git status
- `gd` — git diff
- `glg` — git log graph (pretty one-line, all decorated)
- `gfix` — `git absorb --and-rebase` (auto-fixup staged hunks onto the right parents)
- `gdft` — difftastic log (AST-aware diff via `GIT_EXTERNAL_DIFF=difft`)

Modern CLI overrides (use a leading backslash — `\ls`, `\cat` — to reach the original):
- `ls` → `eza --icons`
- `ll` → `eza -lah --icons --git`
- `la` → `eza -a --icons`
- `lt` → `eza --tree --level=2 --icons`
- `cat` → `bat -p`

Misc:
- `clx` → `scc .` (quick LoC + complexity)
- `dush` → `dust` (du tree)
- `dfh` → `duf` (df replacement)
- `psh` → `procs` (ps replacement)
- `rec` → `asciinema rec`

**`grep` is deliberately NOT aliased** — preserves muscle memory on unfamiliar
hosts. `rg` is the ripgrep command; invoke it explicitly.

## CLI tools (in `~/.local/bin/`)

**Install / update:**
```bash
bin/install-user-bins.sh           # install missing, upgrade outdated
bin/install-user-bins.sh --force   # re-install every tool
bin/install-user-bins.sh <name>    # install a single tool
```

**Tools** (grouped):
- Shell UX: atuin · zoxide · starship · direnv · carapace-bin · fzf
- Core CLI replacements: bat · eza · fd · rg · delta · difft · sd · jq
- Git tooling: lazygit · gh-dash · git-absorb · git-branchless · git-who · spr · onefetch · scc
- System: btop · hyperfine · tldr · just · watchexec · asciinema · vhs · yazi · dust · duf · procs
- Bridges: gh · yq
- Shells / editors: zsh · nvim

**Version policy:** pins in the `TOOLS` table are concrete semvers — bump
quarterly via `git diff`. Several tools have `--version` output that doesn't
match the fetcher's semver regex; they re-install on every run — harmless
(eza, gh-dash, sd, git-branchless, spr).

### Known platform quirks on ld5

- Host glibc is 2.38. Several upstream binaries (latest atuin, latest yazi,
  latest onefetch) require glibc 2.39. The committed TOOLS table uses musl
  variants where available and pins older versions where not — working
  versions are installed, just not always the absolute newest.
- nvim AppImage runs without FUSE via `--appimage-extract`. The extracted tree
  lives at `~/.local/share/nvim-appimage/`; `~/.local/bin/nvim` symlinks into it.

## Neovim

Two distros, both installed, both isolated via `NVIM_APPNAME`:

| Command | Distro | Config dir | Data dir |
|---|---|---|---|
| `nvim` | **NvChad** (default) | `~/.config/nvim/` | `~/.local/share/nvim/` |
| `lv` | **LazyVim** (fallback) | `~/.config/nvim-lazy/` | `~/.local/share/nvim-lazy/` |

Both are committed into the dotfiles repo:
- NvChad at `config/nvim/` — user overrides land in `lua/chadrc.lua` (theme
  options), `lua/plugins/init.lua` (extra plugins), `lua/mappings.lua` (extra
  keymaps). The v2.5 starter does NOT auto-load `lua/custom/` (legacy v2.0
  convention); we edit the v2.5 native paths directly.
- LazyVim at `config/nvim-lazy/` — user overrides in `lua/plugins/user.lua`.

### First launch (each distro)

`nvim` or `lv` — the respective plugin manager (NvChad's built-in / lazy.nvim)
fetches plugins on first open. 15–30 seconds. Subsequent launches ~100 ms.

### Keymaps (both distros — functional parity so muscle memory transfers)

| Keymap | Action |
|---|---|
| `<leader>ff` | Find files (Telescope) |
| `<leader>fg` | Live grep |
| `<leader>fb` | Buffers |
| `<leader>fk` | Keymaps |
| `<leader>gg` | Lazygit popup |
| `<leader>gd` | Git preview hunk |
| `<leader>gs` | Git blame toggle |
| `<leader>xx` | Trouble diagnostics |
| `<leader>e`  | Oil floating file manager |
| `gd` | LSP definition |
| `gr` | LSP references |
| `K`  | LSP hover |

Leader = `<space>`.

### LSP servers (auto-installed via Mason)

pyright (python) · rust-analyzer (rust) · gopls (go) · lua-language-server
(lua) · bash-language-server (bash/zsh) · yaml-language-server (yaml) ·
json-lsp (json) · marksman (markdown).

### Known LazyVim treesitter quirk on ld5

The bundled tree-sitter CLI requires glibc 2.39; ld5 is 2.38. Parser builds
fail on first `:TSUpdate`. LazyVim falls back to **prebuilt parsers** fetched
over the network on first interactive open. If you hit missing-parser errors
after first open, run `lv +TSUpdateSync +qa!` once more — LazyVim will retry.

## Atuin cloud sync

Atuin is the Ctrl-R history replacement; history syncs (end-to-end encrypted)
between ld4 and ld5 via `api.atuin.sh`. Config is committed at
`config/atuin/config.toml`; `auto_sync = true, sync_frequency = 5m`.

```bash
atuin status                # shows local vs cloud
atuin sync --force          # force a sync now
atuin logout                # disable sync on this host (keeps local history)
```

## Troubleshooting

### "zsh: command not found" in a new tmux pane

`~/.local/bin/zsh` didn't get installed. Run:
```bash
bin/install-user-bins.sh zsh
tmux source ~/.tmux.conf
```
Then open a fresh pane.

### Shell start feels slow

```bash
hyperfine -m 10 '~/.local/bin/zsh -ic exit'
~/.local/bin/zsh -ic 'zmodload -F zsh/zprof +zsh/zprof; zprof | head -30'
~/.local/bin/zsh -ic 'zinit times'
```

Typical culprits:
- A non-turbo plugin loading at startup — move behind `wait` / `lucid`.
- `compinit` rebuild on every open — `~/.zcompdump*` is cached; if a tool
  install keeps invalidating it, inspect `zsh -ic 'autoload -Uz compinit; compinit -d ~/.zcompdump'`.
- Slow eval-init — `starship explain` breaks down per-module cost.

### atuin isn't syncing between hosts

```bash
atuin status
atuin sync --force
cat ~/.config/atuin/config.toml | grep -E 'auto_sync|sync_'
```

Common: `auto_sync = false` means the config symlink is broken. Re-run
`./install.sh`.

### `nvim` crashes on launch or plugins fail to install

```bash
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
nvim --headless "+Lazy! sync" "+qa!"
```

For LazyVim (`lv`): substitute `nvim-lazy` everywhere.

### Tool not found even after install

```bash
echo $PATH | tr ':' '\n' | grep local
ls -l ~/.local/bin/<tool>
```

If `~/.local/bin` isn't on PATH: re-source `shell/shared.sh`:
```bash
source ~/my_stuff/dotfiles/shell/shared.sh
```

### Starship prompt shows no git info on a big repo

Starship's `git_status` walks the working tree. On repos >10k files it can
exceed the 300 ms `command_timeout` and silently abort. Bump the timeout in
`config/starship.toml` or disable `git_status` per-host via
`~/.zshrc.d/99-local.zsh`:
```zsh
export STARSHIP_CONFIG="$HOME/.config/starship-minimal.toml"
```

### Carapace completions interfere with a specific command

Disable carapace for that command:
```bash
# In ~/.zshrc.d/85-carapace.zsh or 99-local.zsh:
export CARAPACE_HIDDEN=kubectl,helm
```

### `ls` (eza) output too busy on pipes

Aliases apply only to interactive shells; pipes get real `ls`. To force raw
`ls` interactively use `\ls` or `command ls`.

### `install-user-bins.sh` re-installs some tools on every run

Expected for tools whose `--version` output doesn't include a `digit.digit(.digit)?`
pattern: `eza`, `gh-dash`, `sd`, `git-branchless`, `spr`. Cosmetic; the
install step is idempotent (same binary fetched + installed).

## Rollback

### Revert to bash as tmux default

Edit `tmux/tmux.conf.local.tpl`, restore:
```
set -g default-command "exec /bin/bash --login"
set -g default-shell "/bin/bash"
```
Run `sed "s|__HOME__|$HOME|g; s|__USER__|$USER|g" tmux/tmux.conf.local.tpl > ~/.tmux.conf.local` and `tmux source ~/.tmux.conf`.

### Uninstall a single binary

```bash
rm ~/.local/bin/<tool>
```

### Nuke nvim state

```bash
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
rm -rf ~/.local/share/nvim-lazy ~/.local/state/nvim-lazy ~/.cache/nvim-lazy
```

### Full productivity-phase revert

On master:
```bash
git log --oneline | grep -iE 'productivity|zsh|zshrc|nvchad|lazyvim' | head
# Squash-merge of the power-productivity phase gets one SHA on master; revert that.
git revert <sha>
./install.sh       # re-symlinks; without zsh stuff the tmux shell swap reverts too
```

## Cross-reference

- Spec: `docs/superpowers/specs/2026-04-21-productivity-design.md`
- Plan: `docs/superpowers/plans/2026-04-21-productivity.md`
- Execution log: `docs/superpowers/logs/2026-04-21-productivity-execution.md`
- Observability guide (prerequisite): `docs/guides/2026-04-19-observability-user-guide.md`
