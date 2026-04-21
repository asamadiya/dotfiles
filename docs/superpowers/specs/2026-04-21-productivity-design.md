# Productivity Phase Design — zsh + modern CLI + Neovim

Date: 2026-04-21
Scope: second phase of the power-tui dotfiles overhaul. Productivity-layer tooling deferred from the observability phase (spec §13 "deferred to productivity phase").

Follow-up specs (out of scope here): Mac-side dotfiles, NVIDIA driver, netdata, agentic-loop tools (aider, llm, ollama), `mise` for polyglot toolchains, personal-side state repo.

---

## 1. Motivation

The observability phase landed the substrate: tmux telemetry, session continuity (Claude + Copilot), state repo, worktree orchestrator. The daily driver shell and CLI tools remain at their out-of-box AzL3 defaults — bash-only, no modern replacements for ls/find/grep/diff, no interactive git UI, no neovim, no shell history search, no fuzzy finder. This phase closes that gap without touching the observability substrate or the Mac side.

## 2. Principles (extending observability §2)

1. **zsh where you work, bash where it matters for scripts.** tmux panes open zsh; login shell, cron, systemd units, `bootstrap.sh` / `install.sh` / `sync.sh` all stay bash.
2. **Snappy first.** Cold `time zsh -ic exit` target **< 150 ms**. Plugins load turbo-async after the first prompt. No oh-my-zsh.
3. **Every installed tool gets one row.** What it does / why for this persona / alternatives considered / what the community uses. Table form — no novella paragraphs.
4. **Additive, rollback-clean.** Each of the three sub-systems (shell stack, modern CLI binaries, neovim) lands as its own commit set and each can be reverted independently without breaking the others.
5. **No tool auto-install during a Claude session.** Installs are explicit via `bin/install-user-bins.sh` — called from `install.sh` once and idempotent on re-run.
6. **YAGNI ruthlessly.** Tools with no concrete daily use case in this persona's workflow are skipped — the inventory table's "why for this persona" column is the gate.
7. **Carry forward all observability-phase rules:** no Co-Authored-By, no auto-push, git-first, two-identity git config, etc.

## 3. Architecture overview

Three sub-systems, each independent:

| Sub-system | What it delivers | Depends on |
|---|---|---|
| A. Shell stack | zsh interactive (tmux default), zinit turbo plugin loader, modular `~/.zshrc.d/`, starship prompt, atuin+zoxide+direnv+carapace+fzf-tab init | zsh binary (via zsh-bin, no sudo); atuin+zoxide+starship+carapace binaries installed |
| B. Modern CLI binaries | ~30 static binaries into `~/.local/bin/` via `bin/install-user-bins.sh` (idempotent, version-pinned, no tdnf/sudo) | `curl`, `tar` (present) |
| C. Neovim | NvChad at `nvim` / LazyVim at `lv` via `NVIM_APPNAME`; LSPs + tree-sitter + keymaps | nvim ≥ 0.10 AppImage (GitHub releases, no tdnf) |

Cross-cutting: `install.sh` orchestrates all three via a single call to `bin/install-user-bins.sh`. No tdnf anywhere.

### 3.1 Shell-switch mechanism

```
login → bash (/etc/profile, shell/bash_profile, shell/bashrc)
  ↓
tmux → zsh via default-command "exec /bin/zsh --login"
  ↓
zsh loads shell/zshenv → shell/zshrc → shell/zshrc.d/*.zsh (lex order)
```

Bash infrastructure remains functional. Every existing bash script continues to run exactly as before. Users who `ssh host` directly (outside tmux) still get bash — intentional.

### 3.2 Neovim-duality mechanism

nvim 0.9+ supports `NVIM_APPNAME=<name>` which redirects all config/data/state/cache dirs from `nvim/` to `<name>/`. Two isolated distros coexist:

| Command | Appname | Config dir | Data/state/cache |
|---|---|---|---|
| `nvim` | `nvim` (default) | `~/.config/nvim/` (NvChad) | `~/.local/share/nvim/`, `~/.local/state/nvim/`, `~/.cache/nvim/` |
| `lv` (alias `NVIM_APPNAME=nvim-lazy nvim`) | `nvim-lazy` | `~/.config/nvim-lazy/` (LazyVim) | `~/.local/share/nvim-lazy/`, `~/.local/state/nvim-lazy/`, `~/.cache/nvim-lazy/` |

Both install their plugin trees on first launch via their own package managers (lazy.nvim for LazyVim; NvChad's built-in). Neither leaks into the other.

---

## 4. Shell stack — detail

### 4.1 Zsh install — no tdnf

Use **`romkatv/zsh-bin`** (same author as powerlevel10k) — pre-built static zsh binaries for Linux amd64 that install entirely under `~/.local/` with no root, no tdnf, no build toolchain.

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/master/install)" -- -e no -d "$HOME/.local"
```

Lands zsh + associated man pages at `~/.local/bin/zsh`. Works on glibc ≥ 2.17 and musl — AzL3 glibc is well above that threshold.

Tmux references zsh by absolute path (`default-shell "$HOME/.local/bin/zsh"`), so `/etc/shells` does not need an entry.

Alternatives considered:
- **tdnf install zsh** — explicitly rejected per user preference (no tdnf).
- **Source-build (`./configure && make && make install`)** — requires `gcc`, `make`, `ncurses-devel` which brings tdnf back. Out.
- **`conda install zsh`** — drags in a whole conda env. Overkill.

Community: zsh-bin is the go-to "zsh without sudo" on shared servers, in CI images, on minimal distros. 2k+ stars, maintained by a credible author (romkatv).

### 4.2 Plugin manager — zinit turbo

| Tool | Stack | Strengths | Weaknesses |
|---|---|---|---|
| **zinit** (Z-Shell/zinit) | zsh-only, ice-modifier syntax | Turbo-mode async loading (loads plugins AFTER first prompt, so cold start is ~30–50 ms regardless of plugin count). Flexible — conditional loads, wait ice, trigger-load. | Non-trivial syntax. Declarative DSL takes 10 minutes to understand. |
| **antidote** | successor to antibody | Simple plugin-file, fast, minimal | Simpler but no turbo-mode magic — all plugins load on startup. Slower cold start. |
| **znap** | Steve Losh, fastest cold start | Minimal, fast. | Tiny community, less active. |
| **oh-my-zsh** | Venerable | 500+ plugins built in. Easy onboarding. | 150–300 ms startup penalty. Explicitly ruled out. |
| **prezto** | oh-my-zsh alternative | Cleaner than omz. | Still adds overhead; prefers style over snappiness. |

**Community (2024/2025):** zinit + turbo is the modern default for power users optimizing for startup time. Used by LazyVim-style dotfile maintainers and in r/zsh "my config" threads. Antidote remains the easy-mode pick for users who don't want turbo complexity.

**Pick: zinit (turbo).** Matches project_shell_stack memory. Bootstrap auto-installs to `~/.local/share/zinit/zinit.git/` on first zsh launch.

### 4.3 Turbo-loaded plugins (load after first prompt)

| Plugin | Role | Community note |
|---|---|---|
| `zsh-users/zsh-autosuggestions` | History-based ghost text (fish-parity) | Universal in modern zsh setups |
| `zdharma-continuum/fast-syntax-highlighting` | Command-line syntax highlight (fish-parity) | Fork of zsh-syntax-highlighting; ~3× faster |
| `zsh-users/zsh-completions` | 300+ curated completions | Table stakes alongside zsh's builtins |
| `Aloxaf/fzf-tab` | Replaces zsh's completion menu with fzf | Nearly universal for fuzzy users |

**Explicitly skipped: `jeffreytse/zsh-vi-mode`.** Zsh has built-in `bindkey -v` vi-mode. The plugin adds polish (visible mode cursor, surround text objects) but adds startup cost and reconfigures keymaps in ways that occasionally conflict with zinit turbo. Built-in is enough per user call.

### 4.4 Completion layering

Five sources, stacked bottom-up, cumulative coverage:

1. Zsh builtin `_*` completion files (ships with zsh — ~500 tools)
2. `zsh-users/zsh-completions` (community — ~300 more)
3. Tool-native `<cmd> completion zsh` (always current with the tool version) — sourced at init for: `gh`, `kubectl`, `rustup`, `cargo`, `uv`, `gh-dash`, `lazygit --config --completion` (where applicable)
4. `bashcompinit` bridge — sources bash-completion for tools that only ship `.bash` completions
5. `carapace-bin` — ~1000 tools from a single binary, parses `--help` for many more (fish-parity layer)

Plus `fzf-tab` on top as the selection UI.

### 4.5 Eval-init tools (synchronous, startup-critical — each < 5 ms)

- `starship init zsh` — prompt
- `zoxide init zsh` — smart `cd` (`z <dir>`, `zi` for fzf pick)
- `atuin init zsh --disable-up-arrow` — Ctrl-R rewire; up-arrow stays linear per-session
- `direnv hook zsh` — per-dir `.envrc` auto-load
- `carapace _carapace zsh` — completion source

### 4.6 Prompt — starship

`config/starship.toml` (already in repo; reviewed + tuned). Two-line format:

```
 directory  git_branch  git_status  cmd_duration  exit_code
❯
```

Modules ON: `directory`, `git_branch`, `git_commit`, `git_state`, `git_status` (with `ahead_behind`), `cmd_duration`, `status`, `jobs`, `character`.
Modules OFF: `hostname`, `username`, `time`, `battery`, `package`, language-prompts (`python`, `rust`, `go`, …). Minimalist core.

`git_status` uses `--no-renames --untracked-files=normal` to stay fast on large repos. Starship's internal `fetch_command` is skipped (avoids implicit `git fetch`).

### 4.7 History — atuin with cloud sync

- Config at `config/atuin/config.toml` (symlinked to `~/.config/atuin/config.toml`).
- `auto_sync = true`, `sync_frequency = "5m"`, `sync_address = "https://api.atuin.sh"` (default).
- `filter_mode_shell_up_key = "session"` — up-arrow stays linear.
- `update_check = false` — no noisy checks.
- `dialect = "us"`, `style = "compact"`.
- End-to-end encryption is atuin's default (AES on the client; server stores ciphertext only).

**One-time per host** (documented in the user guide, NOT in install.sh — needs an interactive key):

```bash
atuin register -u spopuri -e <email>   # first host only
atuin login                             # each subsequent host, with the same key
atuin sync                              # pull everything to the new host
```

State-repo atuin-DB encrypted-export stays in place as a belt-and-suspenders backup — if atuin cloud ever dies, the encrypted DB is still in `~/lin_code/state/atuin/history.db.age`.

### 4.8 `shell/zshrc.d/` module layout

```
00-path.zsh          # PATH, MANPATH, LD_LIBRARY_PATH
10-env.zsh           # EDITOR, PAGER, LANG, CUDA_HOME, TENSORRT_HOME
20-history.zsh       # HISTFILE, HISTSIZE, SAVEHIST, share-history, etc.
30-opts.zsh          # setopt autocd, globstar, extended_glob, …
40-aliases.zsh       # aliases (see 4.10)
50-modern-cli.zsh    # bat/eza/fd/rg integrations (guarded by command -v)
60-fzf.zsh           # FZF_DEFAULT_OPTS, key-bindings, CTRL-T / ALT-C
70-zoxide.zsh        # eval "$(zoxide init zsh)"
75-atuin.zsh         # eval "$(atuin init zsh --disable-up-arrow)"
80-direnv.zsh        # eval "$(direnv hook zsh)"
85-carapace.zsh      # carapace init
90-starship.zsh      # eval "$(starship init zsh)"
95-pane-log.zsh      # (ALREADY landed in observability phase)
99-local.zsh         # host-specific, gitignored
```

Every `command -v` guard ensures a missing tool doesn't break the shell. `~/.zshrc` is a 6-line bootstrap that sources the `.zshrc.d/*.zsh` files.

### 4.9 Bash coexistence

- `shell/bashrc`, `shell/bash_profile`, `shell/profile` — unchanged. Continue to serve bash-script shells, SSH-direct logins, cron, systemd units.
- New `shell/shared.sh` — small (~20 line) file of env exports (PATH additions, EDITOR, LANG) sourced by **both** bash and zsh to avoid duplication. Written in POSIX-bash-compatible syntax.

### 4.10 Aliases (new — in `shell/zshrc.d/40-aliases.zsh`)

Ported from bashrc + additions:

```
# Claude / Copilot / kube (existing)
alias c='claude' cc='claude --continue' cr='claude --resume' cw='claude --worktree'
alias cp='copilot'
alias k='kubectl'

# Git
alias lg='lazygit'
alias gst='git status' gd='git diff'
alias glg='git log --graph --oneline --all --decorate'
alias gfix='git absorb --and-rebase'
alias gdft='GIT_EXTERNAL_DIFF=difft git log -p --ext-diff'

# Modern CLI overrides (escape via leading backslash to reach original)
alias ls='eza --icons'
alias ll='eza -lah --icons --git'
alias la='eza -a --icons'
alias lt='eza --tree --level=2 --icons'
alias cat='bat -p'               # \cat for original
# grep stays — user prefers native grep on unknown hosts; rg available as rg

# Stats / inspection
alias clx='scc .'
alias dush='dust'
alias dfh='duf'
alias psh='procs'

# Recording
alias rec='asciinema rec'
```

**`grep` NOT aliased to `rg`** — user preference: preserve muscle memory on unfamiliar hosts. `rg` stays a distinct command.

### 4.11 Tmux shell swap (one hunk in `tmux/tmux.conf.local.tpl`)

```
set -g default-command "exec /bin/zsh --login"
set -g default-shell "/bin/zsh"
```

The existing `exec /bin/bash --login` comment stays nearby for quick fallback.

---

## 5. Binary install — unified, no tdnf

### 5.1 Version policy

**Pin to "latest stable release as of phase-landing date"** (2026-04-21 at plan execution). Two reasons:

1. **Reproducibility.** Re-running `install-user-bins.sh` months later installs the same versions the spec was tested against. No silent drift.
2. **Explicit bump ritual.** Upgrading a tool is a visible `git diff` on the TOOLS table — bumps are reviewable, not accidental. Quarterly bump chore (15 min).

For tools where GitHub publishes a `releases/latest/download/...` redirect, the installer script still references pinned tags so the download URL is reproducible across time. A separate `bin/install-user-bins.sh --check-latest` flag (future) compares pins to upstream HEAD and prints a bump proposal.

**Implementer responsibility at plan-landing:** verify each pin against the tool's `github.com/<org>/<repo>/releases` page at the time of implementation. Bump to the newest stable tag from the last ~3 months. Avoid pre-release / beta tags. Commit the updated pins in the first installer commit.

### 5.2 `bin/install-user-bins.sh` structure

Single idempotent bash script. Declarative table:

```bash
# Versions pinned to latest stable as of 2026-04-21 — verify at implementation
# time and bump to newest stable if a newer tag exists.
declare -A TOOLS=(
  [zsh]=latest-zsh-bin          # via romkatv/zsh-bin installer (special path)
  [nvim]=stable                 # via neovim/neovim releases/stable/download/*.appimage
  [gh]=latest                   # cli/cli releases (verify pin at install time)
  [yq]=latest                   # mikefarah/yq releases
  [direnv]=latest               # direnv/direnv releases
  [atuin]=latest                # atuinsh/atuin
  [bat]=latest                  # sharkdp/bat
  [btop]=latest                 # aristocratos/btop
  [carapace-bin]=latest         # rsteube/carapace-bin
  [delta]=latest                # dandavison/delta
  [difftastic]=latest           # Wilfred/difftastic
  [duf]=latest                  # muesli/duf
  [dust]=latest                 # bootandy/dust
  [eza]=latest                  # eza-community/eza
  [fd]=latest                   # sharkdp/fd
  [fzf]=latest                  # junegunn/fzf
  [gh-dash]=latest              # dlvhdr/gh-dash
  [git-absorb]=latest           # tummychow/git-absorb
  [git-branchless]=latest       # arxanas/git-branchless
  [git-who]=latest              # sinclairtarget/git-who
  [hyperfine]=latest            # sharkdp/hyperfine
  [jq]=latest                   # jqlang/jq (skip if already installed globally)
  [just]=latest                 # casey/just
  [lazygit]=latest              # jesseduffield/lazygit
  [onefetch]=latest             # o2sh/onefetch
  [procs]=latest                # dalance/procs
  [ripgrep]=latest              # BurntSushi/ripgrep (skip if already installed)
  [scc]=latest                  # boyter/scc
  [sd]=latest                   # chmln/sd
  [spr]=latest                  # ejoffe/spr
  [starship]=latest             # starship/starship
  [tealdeer]=latest             # dbrgn/tealdeer
  [vhs]=latest                  # charmbracelet/vhs
  [watchexec]=latest            # watchexec/watchexec
  [yazi]=latest                 # sxyazi/yazi
  [zoxide]=latest                # ajeetdsouza/zoxide
  [asciinema]=latest            # asciinema/asciinema
)
```

Every `latest` entry is **replaced with a concrete semver tag** by the implementer at plan-landing time — no runtime resolution. The word `latest` in the spec is shorthand for "bump to the newest stable at execution time."

**Special-case installers** (two entries with non-standard install paths):
- `zsh` → invoke the `zsh-bin` installer (§4.1).
- `nvim` → fetch AppImage from `https://github.com/neovim/neovim/releases/download/<tag>/nvim-linux-x86_64.appimage`, `chmod +x`, and either run directly or `--appimage-extract` and symlink the extracted `squashfs-root/usr/bin/nvim`.

All other entries use a generic curl+extract+install helper function parameterised by `(tool_name, version, github_repo, asset_pattern)`.

Per-tool a fetcher function that:
1. Reads pinned version.
2. Probes `~/.local/bin/<tool> --version` — skip if match.
3. Curls the GitHub release tarball for `linux-x86_64-gnu` (or the tool's named variant).
4. SHA256-verifies if the release publishes `SHA256SUMS` (atuin, bat, delta, eza, fd, rg, sd, zoxide, starship do; others fall back to size-check).
5. Extracts + installs as `install -m755` to `~/.local/bin/<tool>`.
6. For tools with shell-completion scripts inside their release: extracts completion files to `~/.local/share/zsh/site-functions/` (zsh) and `~/.local/share/bash-completion/completions/` (bash).

### 5.2 Tool inventory (full table with rationale)

| Tool | What it does | Why for this persona | Alternatives considered | What the community uses |
|---|---|---|---|---|
| **atuin** | SQLite-backed shell history; Ctrl-R TUI with filter by cwd/host/exit | Cross-host history (cloud sync) lets ld4 history show up on ld5. Addresses the "what did I do yesterday" question across machines. | mcfly (ranked but smaller project), hstr (older C tool), hishtory (similar, smaller community) | atuin dominant in 2024+ dotfile repos |
| **bat** | `cat` with syntax highlight + git gutter | Code review in pager form; pipe-friendly with `-p` | No real alternative in this niche | Universal default |
| **btop** | Resource monitor — CPU, mem, net, disk, GPU, procs (mouse-clickable) | Richer than htop; GPU section is a free win once driver lands | htop (kept as fallback), bottom (btm — Rust, fast), glances | btop is the 2023+ headline pick |
| **carapace-bin** | Single binary providing completions for ~1000 tools; parses `--help` for many more | The fish-parity completion layer for zsh | Manual per-tool completions; none matches breadth | Rising default in modern zsh dotfiles |
| **delta** (dandavison) | Syntax-highlighted git diff pager | Daily use; huge readability win on diffs | diff-so-fancy (abandoned), difftastic (semantic — used separately) | delta is the universal 2024 default |
| **difftastic** | AST-aware semantic diff | Shows moved functions and structural changes, not line churn | Traditional line diff (delta), patdiff | Power-user tool via `GIT_EXTERNAL_DIFF` |
| **duf** | `df` replacement; colored, grouped | Minor but daily-visible win | gdu, diskus | Common in modern dotfile setups |
| **dust** | `du` replacement; tree view | Find disk hogs in seconds | ncdu (interactive — kept as alt), gdu (TUI) | Popular in Rust-CLI adopters |
| **eza** | `ls` replacement; icons, git status, tree | Constant use; git-aware listing | lsd (active fork of exa), tree (for tree view only) | eza is the 2023+ pick (exa unmaintained) |
| **fd** | `find` replacement; sane defaults, gitignore-aware | `find` is painful; fd is instant | native `find` (worth keeping), fdfind (Debian rename) | Universal |
| **fzf** | Fuzzy finder | Key-binding driven (Ctrl-T, Alt-C, Ctrl-R via atuin) | skim (sk — Rust fork), peco | fzf is THE pick |
| **gh-dash** | TUI dashboard over `gh` for PRs/issues across repos | Work-side only (`~/lin_code/`); scratchpad for PR review | lazygit's gh integration (weaker), raw `gh pr list` + fzf | Active, recommended in r/github |
| **git-absorb** | Auto-fixup: staged hunks → fixup commits targeting correct parents | Daily fixup flow | Manual `git commit --fixup`, git-revise | Power-user favorite |
| **git-branchless** | Local stacked-log (`git sl`), `git move`, `git undo` | Parallel-work navigation + undo safety | sapling (too disruptive), ghstack (legacy) | Cult following; complementary to spr |
| **git-who** | Fast blame-plus with filters | Code archaeology | `git blame` (slower, less filterable), git-quick-stats (less focused) | Niche but strong adoption in 2024 |
| **hyperfine** | CLI benchmarking | Measure startup times (shell, nvim); verify perf fixes | `time` (worse), bench | Default benchmarking tool |
| **jq** | JSON query (if not present) | Pervasive — Claude statusline parses with it | gojq, fx (interactive) | Universal |
| **just** | Makefile-ish task runner | Committed `justfile` per project; agent loops, test watches | Make (tab hell), npm scripts (language-specific), task | Rising default in polyglot repos |
| **lazygit** (jesseduffield) | Git TUI — hunk staging, interactive rebase, stash, bisect | Daily driver for 90% of git ops | gitui (Rust, faster on huge repos), tig (read-only, weaker staging), NeogitNvim (editor-bound) | Headline pick — universal in 2024 |
| **onefetch** | One-shot repo summary | Context on entering a new repo (on-demand, not auto) | scc (stats), git-quick-stats (menu) | Fun, popular |
| **procs** | `ps` replacement; tree, colored, regex | Process inspection with better ergonomics | htop (interactive only), btm | Common Rust-CLI pick |
| **ripgrep** (`rg`) | `grep` replacement; gitignore, parallel | Already heavily used; install if missing | ag (older), ack (Perl) | Universal (rg is the standard) |
| **scc** (boyter) | LoC + complexity estimate | Code stats | tokei (older, slower), cloc (slow) | Default in 2024 |
| **sd** | `sed` replacement; readable regex | Simple text substitution | sed itself (kept), awk | Growing adoption |
| **spr** (ejoffe) | Stacked-PR tool for GitHub | Work-side stacked work without Graphite (org policy) | Graphite (not allowed per user), manual gh + rebase | Picked via user brainstorm |
| **starship** | Cross-shell prompt | Already selected — cross-shell config, snappy | powerlevel10k (zsh-only), pure (minimal) | 2023+ universal default |
| **tealdeer** (`tldr`) | Simplified man pages | Example-first command help | man (kept), cheat, navi | `tldr` is universal |
| **vhs** | Terminal recording → gif/mp4 via script | Reproducible demos | asciinema (recording), agg (cast → gif) | Complements asciinema |
| **watchexec** | File-watch runner; re-run cmd on change | `watchexec -e py pytest` for TDD loops | entr (older, simpler), nodemon (JS-specific) | Default modern file-watcher |
| **yazi** | Async terminal file manager; image preview | Rare but high-value when needed | broot (alt), ranger (Python, slower), lf | Rising — currently popular |
| **zoxide** | Frecency-ranked `cd` | `z foo` daily; `zi` for fzf pick | autojump, fasd | 2023+ universal default |
| **asciinema** | TTY recording | `rec` alias; session recordings to state repo | terminalizer (heavier) | Universal for terminal demos |

**Explicit skips (with rationale):**
- `mcfly`, `hstr` — atuin picked.
- `broot`, `ranger`, `lf` — yazi picked.
- `lsd` — eza picked.
- `zellij` — tmux retained.
- `chezmoi` — this repo IS the dotfiles manager.
- `nvtop`, `nvitop` — no NVIDIA driver on ld5 (GPU-driver install is a separate spec).
- `tig` — overlaps with lazygit.
- `gitui` — overlaps with lazygit; revisit only if performance on large repos becomes an issue.
- `commitizen` / `conventional-commits` — defer until auto-changelog becomes a need.
- `mise`, `asdf` — polyglot runtime managers; separate future spec.

### 5.3 No tdnf

Zero tdnf calls in this phase. Every binary ships as a user-local install under `~/.local/bin/`. `install-user-bins.sh` is the single installer — no sudo, no package manager, no second script.

Rationale: system package manager binaries drift slowly (AzL3's tdnf often ships months-old versions), pin to OS releases, and require sudo. User-local static binaries from GitHub releases give current versions and install rollback is a single `rm`.

Observability phase's `bin/git-lfs`, `bin/bats`, `bin/shellcheck`, `bin/age` installs followed the same pattern already and work fine on ld5.

---

## 6. Neovim — detail

### 6.1 Binary install (no tdnf)

Fetch the nvim AppImage from GitHub releases stable tag:
```
https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.appimage
```

Install to `~/.local/bin/nvim` (chmod +x). If FUSE is not available on the host (common in VM images), run `./nvim-linux-x86_64.appimage --appimage-extract` once and symlink the extracted `squashfs-root/usr/bin/nvim` to `~/.local/bin/nvim`.

Pin a specific `v0.10.x` tag at plan-landing rather than the `stable` alias so the install is reproducible. Both distros require nvim ≥ 0.10 for treesitter + LSP API stability; pinning to the newest 0.10.x at the time of landing is ideal.

### 6.2 NvChad (default `nvim`)

**Install:** `git clone --depth 1 https://github.com/NvChad/starter ~/.config/nvim`, then convert to a dotfiles-managed checkout: `mv ~/.config/nvim ~/.config/nvim.upstream; git clone <dotfiles> ~/.config/nvim -- sparse-checkout config/nvim/`. Alternative, cleaner: commit the NvChad starter snapshot into `dotfiles/config/nvim/` and symlink.

**Pick:** **commit the NvChad starter to the dotfiles repo** at `config/nvim/` — provides reproducibility, clear git diff on user changes, and lets `install.sh` just symlink `~/.config/nvim -> $DOTFILES/config/nvim/`. Plugins themselves are NOT vendored — they live in `~/.local/share/nvim/` (NvChad manages them via its bundled plugin manager).

**User overrides** under `config/nvim/lua/custom/` (NvChad's official extension point):
- `chadrc.lua` — colorscheme = `catppuccin-mocha`, theme-toggle keybind.
- `plugins.lua` — user plugins (see §6.4).
- `mappings.lua` — extra keymaps (see §6.5).

### 6.3 LazyVim (fallback `lv`)

**Install:** commit the LazyVim starter snapshot into `dotfiles/config/nvim-lazy/` and symlink `~/.config/nvim-lazy -> $DOTFILES/config/nvim-lazy/`.

**User overrides** under `config/nvim-lazy/lua/plugins/user.lua`:
- LazyVim extras matching NvChad parity (see §6.4).

**Alias:** `lv='NVIM_APPNAME=nvim-lazy nvim'` in `shell/zshrc.d/40-aliases.zsh`.

### 6.4 Plugin parity (both distros)

Both get the same functional set so muscle memory transfers between them:

| Category | Plugin | Purpose |
|---|---|---|
| Fuzzy | `nvim-telescope/telescope.nvim` | Files, grep, buffers, keymaps, git |
| LSP | `neovim/nvim-lspconfig` + `williamboman/mason.nvim` | LSP servers auto-install per-language |
| Completion | `hrsh7th/nvim-cmp` + LSP source + snippets (luasnip) | Completion UX |
| Syntax | `nvim-treesitter/nvim-treesitter` | Better highlighting + text objects |
| Git | `lewis6991/gitsigns.nvim` | Gutter diff + stage-hunk |
| Git TUI | `kdheepak/lazygit.nvim` | `<leader>gg` opens lazygit |
| Files | `stevearc/oil.nvim` | Edit-a-directory-as-buffer |
| Keymap | `folke/which-key.nvim` | Shows keymaps on prefix |
| Diagnostics | `folke/trouble.nvim` | LSP diagnostic tray |
| Theme | `catppuccin/nvim` | Matches tmux + starship |
| Status | Lualine (NvChad comes with its own; LazyVim uses lualine too) | Status bar |
| Editor | `kylechui/nvim-surround` | Surround text-objects |
| Misc | `folke/flash.nvim` | Motion (replaces leap/hop) |

**Intentionally excluded for now:** nvim-dap (debugger), copilot.nvim (user has Copilot CLI separately; integration is a future decision), avante.nvim (AI assist — separate phase).

### 6.5 LSPs via Mason (both distros)

Auto-installed on first open of a matching filetype:

- `lua_ls` (lua — nvim config itself)
- `pyright` (python)
- `rust-analyzer` (rust)
- `gopls` (go)
- `bashls` (bash/zsh scripts)
- `yamlls` (yaml)
- `jsonls` (json)
- `marksman` (markdown)

### 6.6 Tree-sitter parsers

Installed on first open per filetype:

`lua, python, rust, go, bash, zsh, yaml, json, markdown, markdown_inline, toml, tmux, gitcommit, diff, dockerfile, make, regex, vim, vimdoc`

### 6.7 Keymaps (both distros)

Leader = `<space>` (convention). Vim-native hjkl preserved.

| Keymap | Action |
|---|---|
| `<leader>ff` | Telescope files |
| `<leader>fg` | Telescope live_grep |
| `<leader>fb` | Telescope buffers |
| `<leader>fk` | Telescope keymaps |
| `<leader>gs` | Gitsigns toggle blame |
| `<leader>gg` | Lazygit popup |
| `<leader>gd` | Gitsigns preview_hunk |
| `<leader>xx` | Trouble diagnostics |
| `<leader>e` | Oil floating (directory edit) |
| `<leader>lr` | LSP rename |
| `<leader>la` | LSP code_action |
| `gd` | LSP definition |
| `gr` | LSP references |
| `K` | LSP hover |
| `<leader>w` | Save (overrides default write) |

### 6.8 First-run behavior

- First `nvim` (NvChad): on open, NvChad bootstraps plugins in `~/.local/share/nvim/`. 15–30 second first launch; subsequent launches ~100 ms.
- First `lv` (LazyVim): similar — lazy.nvim bootstraps plugins in `~/.local/share/nvim-lazy/`.
- LSPs install on first open of matching filetype (Mason auto-install).

---

## 7. File and wiring inventory

### 7.1 New files (dotfiles/)

| Path | Purpose |
|---|---|
| `bin/install-user-bins.sh` | Sole installer for every user-local binary (zsh, nvim, ~30 CLI tools). Idempotent, version-pinned. Invoked from `install.sh`. No tdnf, no sudo. |
| `shell/zshenv` | PATH + env always-loaded |
| `shell/zshrc` | Bootstrap — sources zshrc.d/*.zsh |
| `shell/zshrc.d/00-path.zsh` — `90-starship.zsh` | Modular init (see §4.8) |
| `shell/shared.sh` | POSIX-compat env exports sourced by both bash and zsh |
| `config/atuin/config.toml` | Atuin cloud-sync + Ctrl-R config |
| `config/nvim/` | NvChad starter + user overrides |
| `config/nvim-lazy/` | LazyVim starter + user overrides |

### 7.2 Modified files (dotfiles/)

| Path | Change |
|---|---|
| `tmux/tmux.conf.local.tpl` | `default-command` + `default-shell` → zsh |
| `install.sh` | Symlink zsh dotfiles, nvim configs, atuin config; invoke `bin/install-user-bins.sh`. No tdnf block. |
| `sync.sh` | `BIN_SCRIPTS` gains `install-user-bins.sh` |
| `shell/bashrc` | (Minimal) source `shell/shared.sh` at top |
| `README.md` | New "Shell + CLI tools" section, new "Neovim" section |
| `CLAUDE.md` | Key Scripts table gets new installer rows |
| `CHANGELOG.md` | Dated block for this phase |
| `env.txt` | Regenerated post-install from `command -v` probes and `~/.local/bin/` inventory (no `tdnf list installed` dependency) |

### 7.3 Unchanged

- `shell/bash_profile`, `shell/profile`, `shell/inputrc` — bash-path only, functional.
- Every observability-phase script and tmux config (`bin/wt`, sysstat, state-snapshot, session-end-autocommit, etc.).

---

## 8. Acceptance criteria

Verified on ld5 with `power-productivity` (or equivalent) branch merged:

1. **Zsh is the tmux shell.** `tmux new-window` → `echo $SHELL` → `/bin/zsh`. `ps -p $$` → `zsh`.
2. **Bash still works.** `ssh ld5` direct (outside tmux) → bash. `bash -c 'echo ok'` → ok.
3. **Cold-start budget.** `time zsh -ic exit` (cold, no cached completion) → wall-time **< 150 ms**. Warm (cached) → **< 50 ms**.
4. **Turbo plugins load.** First prompt appears quickly; second prompt onward, autosuggestions + syntax-highlighting are active. `zinit times` shows plugins loaded in background after prompt.
5. **Starship renders.** Two-line prompt; directory + branch + dirty glyph (`✗`) + exit code in a dirty repo.
6. **Atuin sync.** `atuin sync --force` after login returns OK. Running a command on ld5 → visible in `Ctrl-R` on ld4 (or vice versa) within 5 min.
7. **Modern CLI overrides.** `ls` renders eza's icons + git column. `\ls` falls back to raw `ls`. `cat foo.sh` invokes bat. `find …` still works (find NOT aliased — user preserves muscle memory; fd is distinct).
8. **fzf bindings.** `Ctrl-T` lists files, `Alt-C` cds to fzf-picked dir. `Ctrl-R` opens atuin (NOT fzf-history — atuin supersedes).
9. **zoxide.** `z dotfiles` jumps to `~/my_stuff/dotfiles`. `zi` opens fzf picker.
10. **carapace completions.** Type `kubectl get po<TAB>` → suggestions include `pods` etc. via carapace even without explicit per-tool completion install.
11. **lazygit binding.** In any git repo: `lg` → lazygit TUI. `<leader>gg` inside nvim opens lazygit.nvim popup.
12. **Install idempotent.** `bin/install-user-bins.sh` first run: installs all missing binaries. Second run: prints "already installed vX.Y.Z" for each, does nothing. `--force` reinstalls.
13. **Every binary is on PATH.** `for t in atuin bat btop carapace-bin delta difftastic duf dust eza fd fzf gh-dash git-absorb git-branchless git-who hyperfine jq just lazygit onefetch procs rg scc sd spr starship tldr vhs watchexec yazi zoxide asciinema; do command -v $t >/dev/null || echo "MISSING: $t"; done` → no MISSING lines.
14. **Two-identity still correct.** `cd ~/my_stuff/... && git config user.email` → `asamadiya@…`; `cd ~/lin_code/... && git config user.email` → work email. (Regression check from observability phase.)
15. **NvChad opens.** `nvim` → NvChad dashboard; `<leader>ff` opens Telescope files; `<leader>gg` opens lazygit; `:LspInfo` in a `.py` file shows pyright attached.
16. **LazyVim opens.** `lv` → LazyVim dashboard, plugins install on first launch, `<leader>ff` works identically.
17. **NVIM_APPNAME isolation.** `ls ~/.config/nvim ~/.config/nvim-lazy` — two distinct dirs. `ls ~/.local/share/nvim ~/.local/share/nvim-lazy` — two distinct plugin trees.
18. **Observability regression.** `bin/sysstat.sh` still renders; state-snapshot.timer still active; session-end-autocommit still fires on Claude exit; claude-statusline shows dirty glyph.
19. **tmux prefix bindings still work.** `prefix+w` tree picker, `prefix+C-w` wt jump, `prefix+C-c` / `C-p` agents, `prefix+L` / `M-L` pane-log.
20. **User guide exists.** `docs/guides/2026-04-21-productivity-user-guide.md` is written as the final step of the implementation plan — covers zsh migration, all new aliases, install-user-bins flow, atuin registration flow, nvim cheatsheet (both distros), NVIM_APPNAME explanation, troubleshooting, rollback.

---

## 9. Rollback strategy

Per-sub-system rollback is one `git revert` plus a filesystem cleanup:

- **Shell stack:** revert phase commits; `tmux source ~/.tmux.conf` to restore bash default-command. `rm -rf ~/.local/share/zinit ~/.cache/zinit ~/.zcompdump` to clean zinit artifacts.
- **Modern CLI binaries:** `rm ~/.local/bin/<tool>` per tool. `bin/install-user-bins.sh --uninstall` as a one-shot cleanup flag is a future add; today manual.
- **NvChad / LazyVim:** `rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim` (and the `nvim-lazy` variants). Dotfiles still symlink them, but the cached state is what makes first-launch slow — removing it returns to pristine.
- **Atuin cloud:** `atuin logout` on each host removes sync; local history continues. `atuin uninstall` if going further.

Every sub-system is committed atomically so `git revert <sha>` undoes its surface area cleanly.

---

## 10. Open questions / risks

| # | Risk / question | Mitigation |
|---|---|---|
| 1 | Zinit turbo-mode conflicts: some plugins don't like being loaded after the prompt (rare). | All plugins in §4.3 are tested with zinit turbo by their upstream. If one misbehaves, drop to non-turbo for that plugin only. |
| 2 | Starship's git_status on very large repos (LinkedIn-scale) can be slow. | `git_status.disabled = true` per-host via `99-local.zsh` if you hit a problem repo. Starship reports > 150ms per call in the status line duration if it fires. |
| 3 | Atuin cloud availability (api.atuin.sh). | Belt-and-suspenders: the age-encrypted atuin DB in state repo is your backup. Transition to self-hosted atuin-server in a future phase if the free tier changes. |
| 4 | NvChad starter API changes between versions. | Pin the upstream snapshot in the dotfiles repo and bump explicitly. User upgrades are manual and visible in git diff. |
| 5 | LazyVim starter — same API-drift concern. | Same pinning strategy. |
| 6 | nvim 0.10+ requirement. | `bin/install-user-bins.sh` probe + AppImage fallback. Fail loudly if version < 0.10. |
| 7 | `carapace-bin` completion breadth may collide with tool-native completions (duplicate entries). | Source-order matters — tool-native first, carapace last. Documented in `85-carapace.zsh`. |
| 8 | `bashcompinit` bridge may slow first completion attempt. | Lazy-load: bashcompinit runs inside a function called on first TAB, not at shell start. |
| 9 | Tool-version drift over time (GitHub releases bump). | Version pin table in `install-user-bins.sh` is the single source of truth. Quarterly bump is a 15-minute chore. |
| 10 | Git alias conflicts with user's muscle memory. | `grep` is deliberately NOT aliased. `ls` → eza is aliased (benefit >> cost) but `\ls` reaches original. |
| 11 | First-time `nvim` launch is slow (plugin install). | Documented in user guide; user knows to expect it. |

---

## 11. Out of scope (deferred to follow-up specs)

- Mac-side dotfiles (Brewfile, Ghostty/WezTerm, SSH `ControlMaster`, Maccy / Raycast, shared starship config).
- NVIDIA driver + CUDA stack (unlocks GPU segment, nvitop, DCGM, py-spy-GPU).
- `netdata` observability dashboard.
- Agentic-loop tools (aider, llm, ollama) and their git-first session capture.
- `mise` (or `asdf`) for polyglot language runtimes (Python / Node / Rust / Go).
- Personal-side state repo (`~/my_stuff/state`).
- ld4 rollout — this phase lands on ld5 first; ld4 gets a one-line `bootstrap.sh` once the phase is merged to master and verified here.

---

## 12. Related memories

- `user_profile.md` — vim/tmux native, keyboard-first, tmux prefix Ctrl+Space.
- `feedback_git_first.md` — every tool choice weighted for git integration.
- `feedback_tool_selection.md` — rationale + alternatives + community per tool (this spec complies).
- `feedback_terse_responses.md` — terse prose, tables over paragraphs.
- `project_my_stuff_layout.md` — two-identity authoring enforcement (unchanged).
- `project_shell_stack.md` — zsh interactive + bash scripts, zinit turbo, no oh-my-zsh, < 150 ms cold start (this spec realizes).
- `project_state_repo.md` — atuin export as backup even with cloud sync (unchanged).
- `feedback_yolo_resume.md` — observability-phase defaults stay live across this phase.

---

## 13. Final deliverable

As with observability, the closing task of the implementation plan is the user guide at `docs/guides/2026-04-21-productivity-user-guide.md` — covering zsh migration, every new alias, install-user-bins flow, atuin registration, nvim cheatsheet for both distros, NVIM_APPNAME explanation, troubleshooting, rollback. Written from the finished state, not from the plan.
