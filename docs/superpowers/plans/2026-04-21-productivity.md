# Productivity Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the productivity substrate on branch `power-productivity` in `~/my_stuff/dotfiles`: zsh (via zsh-bin, no sudo) as tmux's default shell, zinit turbo + modular `~/.zshrc.d/*`, ~30 modern CLI binaries into `~/.local/bin/` via a single idempotent `bin/install-user-bins.sh`, NvChad as `nvim` and LazyVim as `lv` (via `NVIM_APPNAME`). All commits local (no push).

**Architecture:** Three independent sub-systems landing additively — shell stack, CLI binaries, neovim. One unified `bin/install-user-bins.sh` handles every binary install (no tdnf, no sudo). Bash infrastructure stays intact for scripts / direct SSH / cron. Tests-first where practical: bats for shell scripts, `shellcheck` via `bin/lint-shell.sh`, live smoke tests for tmux + nvim integration, cold-start budget (`time zsh -ic exit < 150 ms`).

**Tech Stack:** bash 5.x (scripts), zsh 5.9+ via zsh-bin (interactive), tmux 3.5a (existing), `romkatv/zsh-bin`, `Z-Shell/zinit`, starship, atuin (cloud sync), zoxide, direnv, carapace-bin, fzf-tab, fzf, Mason/Treesitter via nvim, NvChad + LazyVim, bats-core + shellcheck for test tooling. All tools land under `~/.local/bin/` — nothing leaves user space.

**Version policy per spec §5.1:** the TOOLS table uses shorthand `latest` — the implementer **must** resolve each to a concrete semver tag from `github.com/<org>/<repo>/releases` at execution time, and commit the concrete pins. This plan cites example pins valid as of 2026-04-21; verify each before landing.

---

## Prerequisites (once per host, before Task 0)

Most prereqs are already satisfied from the observability phase:

- [ ] Confirm on branch: `cd ~/my_stuff/dotfiles && git rev-parse --abbrev-ref HEAD` → `power-productivity`.
- [ ] `command -v curl tar git bats shellcheck jq` — all present (observability phase).
- [ ] `~/.local/bin/` exists and is on `PATH`.
- [ ] `~/.tmux.conf.local` has been regenerated recently (was touched in observability phase).

No other one-time setup. Installs happen via the tasks below.

---

## Task 0 — Branch + infra sanity

Ensure the plan's starting state. No artifacts produced; purely a gate.

**Files:** none (verification only).

- [ ] **Step 1: Confirm branch + clean tree**

Run:
```bash
cd ~/my_stuff/dotfiles
git rev-parse --abbrev-ref HEAD
git status --short
```
Expected: branch `power-productivity`, clean tree (no uncommitted edits outside the already-committed productivity spec).

- [ ] **Step 2: Confirm test infra**

Run:
```bash
bats --version
shellcheck --version
bin/lint-shell.sh; echo "LINT_EXIT=$?"
```
Expected: both tools report versions; lint exits 0.

- [ ] **Step 3: No commit needed**

This task is a gate. Proceed to Task 1.

---

## Task 1 — `bin/install-user-bins.sh` scaffold with generic fetcher

Produces the unified installer as a minimal working skeleton that installs a single smoke-test tool (fzf — small, fast, ubiquitous). The generic `install_tool` function is the load-bearing code every later task reuses.

**Files:**
- Create: `bin/install-user-bins.sh`
- Create: `tests/bats/install-user-bins.bats`

- [ ] **Step 1: Write `bin/install-user-bins.sh`**

```bash
#!/usr/bin/env bash
# install-user-bins.sh — idempotent installer for user-local CLI binaries.
# Every tool lands under ~/.local/bin/. No tdnf, no sudo.
#
# Usage:
#   install-user-bins.sh          # install missing / bump outdated tools
#   install-user-bins.sh --force  # re-install every tool regardless
#   install-user-bins.sh <tool>   # install just one tool (by table key)
#
# Version policy: TOOLS[<name>]_VERSION pins are the source of truth.
# Each value is a concrete semver (not "latest"). Bump quarterly.

set -euo pipefail

BINDIR="${BINDIR:-$HOME/.local/bin}"
TMPDIR="${TMPDIR:-/tmp}"
mkdir -p "$BINDIR"

FORCE=0
SINGLE=""
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) SINGLE="$arg" ;;
  esac
done

warn() { printf 'install-user-bins: %s\n' "$*" >&2; }
log()  { printf '  %s\n' "$*"; }

# --- generic fetcher ---------------------------------------------------------
# install_tool <name> <version> <repo> <asset_tmpl> <bin_in_archive> [--skip-version-check]
#
# <asset_tmpl> may reference {v} (version) and {V} ("v" prefix + version).
# <bin_in_archive> is the binary's path INSIDE the extracted tarball, or "-"
#                  if the downloaded file IS the binary (no archive).

install_tool() {
  local name="$1" version="$2" repo="$3" asset_tmpl="$4" bin_in_archive="$5"
  local skip_check="${6:-}"

  local installed_version=""
  if [[ -x "$BINDIR/$name" && -z "$skip_check" ]]; then
    installed_version=$("$BINDIR/$name" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)
  fi

  if (( ! FORCE )) && [[ "$installed_version" == "$version" ]]; then
    log "$name $version (already installed)"
    return 0
  fi

  local V="v$version" v="$version"
  local asset="${asset_tmpl//\{v\}/$v}"
  asset="${asset//\{V\}/$V}"
  local url="https://github.com/$repo/releases/download/$V/$asset"

  log "fetching $name $version from $url"
  local work; work=$(mktemp -d)
  trap 'rm -rf "$work"' RETURN

  if ! curl -fsSL -o "$work/$asset" "$url"; then
    warn "$name: download failed ($url)"
    return 1
  fi

  local src=""
  case "$asset" in
    *.tar.gz|*.tgz) tar xzf "$work/$asset" -C "$work"; src="$work/$bin_in_archive" ;;
    *.tar.xz)       tar xJf "$work/$asset" -C "$work"; src="$work/$bin_in_archive" ;;
    *.zip)          unzip -q "$work/$asset" -d "$work"; src="$work/$bin_in_archive" ;;
    *)              # single-file binary
                    src="$work/$asset" ;;
  esac

  if [[ "$bin_in_archive" == "-" ]]; then src="$work/$asset"; fi

  if [[ ! -f "$src" ]]; then
    warn "$name: expected binary at $src not found after extract"
    return 1
  fi

  install -m755 "$src" "$BINDIR/$name"
  log "$name $version installed to $BINDIR/$name"
}

# --- TOOLS table -------------------------------------------------------------
# Keys are one-line arrays of (version repo asset_tmpl bin_in_archive).
# The implementer MUST resolve each version pin below against the tool's
# GitHub releases page AT IMPLEMENTATION TIME. Pins shown here are valid as
# of 2026-04-21 and may be stale.

declare -A TOOL_VERSION=()
declare -A TOOL_REPO=()
declare -A TOOL_ASSET=()
declare -A TOOL_BIN=()

register() { TOOL_VERSION[$1]=$2; TOOL_REPO[$1]=$3; TOOL_ASSET[$1]=$4; TOOL_BIN[$1]=$5; }

# Smoke-test tool (this task only registers fzf; later tasks add the rest).
register fzf 0.56.3 junegunn/fzf 'fzf-{v}-linux_amd64.tar.gz' 'fzf'

# --- dispatch ----------------------------------------------------------------
tools=("${!TOOL_VERSION[@]}")
if [[ -n "$SINGLE" ]]; then tools=("$SINGLE"); fi

failed=0
for t in "${tools[@]}"; do
  if [[ -z "${TOOL_VERSION[$t]:-}" ]]; then
    warn "unknown tool: $t"; failed=$((failed+1)); continue
  fi
  install_tool "$t" "${TOOL_VERSION[$t]}" "${TOOL_REPO[$t]}" "${TOOL_ASSET[$t]}" "${TOOL_BIN[$t]}" \
    || { failed=$((failed+1)); warn "$t install FAILED"; }
done

if (( failed )); then exit 1; fi
echo "install-user-bins: OK"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x bin/install-user-bins.sh
```

- [ ] **Step 3: Write `tests/bats/install-user-bins.bats`**

```bash
#!/usr/bin/env bats

load helpers

@test "--help-like flag that isn't recognised errors with exit 2" {
  run "$DOTFILES_ROOT/bin/install-user-bins.sh" --nope
  [ "$status" -eq 2 ]
}

@test "registered fzf installs to BINDIR" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  BINDIR="$tmp" run "$DOTFILES_ROOT/bin/install-user-bins.sh" fzf
  [ "$status" -eq 0 ]
  [ -x "$tmp/fzf" ]
  "$tmp/fzf" --version | grep -q '0.56.3'
}

@test "unknown-tool arg fails cleanly" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  BINDIR="$tmp" run "$DOTFILES_ROOT/bin/install-user-bins.sh" not-a-tool
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown tool"* ]]
}

@test "second run with --force re-installs" {
  tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
  BINDIR="$tmp" "$DOTFILES_ROOT/bin/install-user-bins.sh" fzf
  ts1=$(stat -c %Y "$tmp/fzf")
  sleep 1
  BINDIR="$tmp" run "$DOTFILES_ROOT/bin/install-user-bins.sh" --force fzf
  [ "$status" -eq 0 ]
  ts2=$(stat -c %Y "$tmp/fzf")
  [ "$ts2" -gt "$ts1" ]
}
```

- [ ] **Step 4: Run tests**

```bash
bats tests/bats/install-user-bins.bats
```
Expected: 4/4 pass. (Tests hit GitHub — network required.)

- [ ] **Step 5: Run lint**

```bash
bin/lint-shell.sh
```
Expected: exit 0.

- [ ] **Step 6: Append to `sync.sh` BIN_SCRIPTS**

Locate the `BIN_SCRIPTS=(...)` array in `sync.sh` and append `install-user-bins.sh`.

- [ ] **Step 7: Commit**

```bash
git add bin/install-user-bins.sh tests/bats/install-user-bins.bats sync.sh
git commit -m "Add bin/install-user-bins.sh scaffold + generic fetcher (fzf smoke)"
```

---

## Task 2 — Add shell-critical tools (atuin, zoxide, starship, direnv, carapace-bin)

These five tools are sourced from the zsh init files in later tasks — install them before zsh lands so the init-evals don't error.

**Files:** Modify `bin/install-user-bins.sh` (add `register` lines).

**Concrete version pins — resolve each against GitHub releases at execution time. Examples valid 2026-04-21:**

| tool | latest-stable example | repo | asset pattern | bin inside |
|---|---|---|---|---|
| atuin | 18.6.1 | atuinsh/atuin | `atuin-x86_64-unknown-linux-gnu.tar.gz` | `atuin-x86_64-unknown-linux-gnu/atuin` |
| zoxide | 0.9.8 | ajeetdsouza/zoxide | `zoxide-{v}-x86_64-unknown-linux-musl.tar.gz` | `zoxide` |
| starship | 1.24.1 | starship/starship | `starship-x86_64-unknown-linux-gnu.tar.gz` | `starship` |
| direnv | 2.37.1 | direnv/direnv | `direnv.linux-amd64` | `-` (single file) |
| carapace-bin | 1.3.2 | carapace-sh/carapace-bin | `carapace-bin_{v}_linux_amd64.tar.gz` | `carapace` |

- [ ] **Step 1: Edit `bin/install-user-bins.sh`**

Below the existing `register fzf ...` line, add:

```bash
register atuin         18.6.1 atuinsh/atuin                 'atuin-x86_64-unknown-linux-gnu.tar.gz'              'atuin-x86_64-unknown-linux-gnu/atuin'
register zoxide        0.9.8  ajeetdsouza/zoxide            'zoxide-{v}-x86_64-unknown-linux-musl.tar.gz'        'zoxide'
register starship      1.24.1 starship/starship             'starship-x86_64-unknown-linux-gnu.tar.gz'           'starship'
register direnv        2.37.1 direnv/direnv                 'direnv.linux-amd64'                                 '-'
register carapace-bin  1.3.2  carapace-sh/carapace-bin      'carapace-bin_{v}_linux_amd64.tar.gz'                'carapace'
```

- [ ] **Step 2: Install the new batch**

```bash
bin/install-user-bins.sh atuin
bin/install-user-bins.sh zoxide
bin/install-user-bins.sh starship
bin/install-user-bins.sh direnv
bin/install-user-bins.sh carapace-bin
```

Expected each: "installed to $BINDIR/<name>".

- [ ] **Step 3: Smoke test each**

```bash
atuin --version
zoxide --version
starship --version
direnv --version
carapace --version
```
Expected: version strings matching pins.

- [ ] **Step 4: Run lint + bats regression**

```bash
bin/lint-shell.sh
bats tests/bats/install-user-bins.bats
```

- [ ] **Step 5: Commit**

```bash
git add bin/install-user-bins.sh
git commit -m "install-user-bins: add atuin, zoxide, starship, direnv, carapace-bin"
```

---

## Task 3 — Core CLI replacements (bat, eza, fd, ripgrep, delta, difftastic, sd, jq)

**Files:** Modify `bin/install-user-bins.sh`.

| tool | example | repo | asset pattern | bin inside |
|---|---|---|---|---|
| bat | 0.25.0 | sharkdp/bat | `bat-{V}-x86_64-unknown-linux-gnu.tar.gz` | `bat-{V}-x86_64-unknown-linux-gnu/bat` |
| eza | 0.21.2 | eza-community/eza | `eza_x86_64-unknown-linux-gnu.tar.gz` | `eza` |
| fd | 10.2.0 | sharkdp/fd | `fd-{V}-x86_64-unknown-linux-gnu.tar.gz` | `fd-{V}-x86_64-unknown-linux-gnu/fd` |
| ripgrep | 14.1.1 | BurntSushi/ripgrep | `ripgrep-{v}-x86_64-unknown-linux-musl.tar.gz` | `ripgrep-{v}-x86_64-unknown-linux-musl/rg` |
| delta | 0.18.2 | dandavison/delta | `delta-{v}-x86_64-unknown-linux-gnu.tar.gz` | `delta-{v}-x86_64-unknown-linux-gnu/delta` |
| difftastic (difft) | 0.62.0 | Wilfred/difftastic | `difft-x86_64-unknown-linux-gnu.tar.gz` | `difft` |
| sd | 1.0.0 | chmln/sd | `sd-{V}-x86_64-unknown-linux-gnu.tar.gz` | `sd-{V}-x86_64-unknown-linux-gnu/sd` |
| jq | 1.7.1 | jqlang/jq | `jq-linux-amd64` | `-` |

Note: `difftastic`'s binary is `difft`. Pass `register difftastic ... difft` to install it as `~/.local/bin/difft` by renaming on the `install` step. Cleanest: register key `difft` not `difftastic`.

- [ ] **Step 1: Edit `bin/install-user-bins.sh` — add the batch**

```bash
register bat     0.25.0  sharkdp/bat                   'bat-{V}-x86_64-unknown-linux-gnu.tar.gz'                    'bat-{V}-x86_64-unknown-linux-gnu/bat'
register eza     0.21.2  eza-community/eza             'eza_x86_64-unknown-linux-gnu.tar.gz'                        'eza'
register fd      10.2.0  sharkdp/fd                    'fd-{V}-x86_64-unknown-linux-gnu.tar.gz'                     'fd-{V}-x86_64-unknown-linux-gnu/fd'
register rg      14.1.1  BurntSushi/ripgrep            'ripgrep-{v}-x86_64-unknown-linux-musl.tar.gz'               'ripgrep-{v}-x86_64-unknown-linux-musl/rg'
register delta   0.18.2  dandavison/delta              'delta-{v}-x86_64-unknown-linux-gnu.tar.gz'                  'delta-{v}-x86_64-unknown-linux-gnu/delta'
register difft   0.62.0  Wilfred/difftastic            'difft-x86_64-unknown-linux-gnu.tar.gz'                      'difft'
register sd      1.0.0   chmln/sd                      'sd-{V}-x86_64-unknown-linux-gnu.tar.gz'                     'sd-{V}-x86_64-unknown-linux-gnu/sd'
register jq      1.7.1   jqlang/jq                     'jq-linux-amd64'                                             '-'
```

- [ ] **Step 2: Install the batch**

```bash
for t in bat eza fd rg delta difft sd jq; do bin/install-user-bins.sh "$t"; done
```

- [ ] **Step 3: Smoke test**

```bash
for t in bat eza fd rg delta difft sd jq; do
  "$HOME/.local/bin/$t" --version | head -1
done
```

- [ ] **Step 4: Lint**

```bash
bin/lint-shell.sh
```

- [ ] **Step 5: Commit**

```bash
git add bin/install-user-bins.sh
git commit -m "install-user-bins: add core CLI replacements (bat/eza/fd/rg/delta/difft/sd/jq)"
```

---

## Task 4 — Git tooling (lazygit, gh-dash, git-absorb, git-branchless, git-who, spr, onefetch, scc)

**Files:** Modify `bin/install-user-bins.sh`.

| tool | example | repo | asset pattern | bin inside |
|---|---|---|---|---|
| lazygit | 0.44.1 | jesseduffield/lazygit | `lazygit_{v}_Linux_x86_64.tar.gz` | `lazygit` |
| gh-dash | 4.10.0 | dlvhdr/gh-dash | `gh-dash_{V}_linux_amd64.tar.gz` | `gh-dash` |
| git-absorb | 0.7.0 | tummychow/git-absorb | `git-absorb-{V}-x86_64-unknown-linux-gnu.tar.gz` | `git-absorb-{V}-x86_64-unknown-linux-gnu/git-absorb` |
| git-branchless | 0.10.0 | arxanas/git-branchless | `git-branchless-{V}-x86_64-unknown-linux-gnu.tar.gz` | `git-branchless-{V}-x86_64-unknown-linux-gnu/git-branchless` |
| git-who | 0.9.0 | sinclairtarget/git-who | `git-who_{V}_linux_amd64.tar.gz` | `git-who` |
| spr | 1.3.6 | ejoffe/spr | `spr_{v}_linux_amd64.tar.gz` | `spr` |
| onefetch | 2.24.0 | o2sh/onefetch | `onefetch-linux.tar.gz` | `onefetch` |
| scc | 3.4.0 | boyter/scc | `scc_Linux_x86_64.tar.gz` | `scc` |

- [ ] **Step 1: Edit `bin/install-user-bins.sh` — add the git batch**

```bash
register lazygit        0.44.1  jesseduffield/lazygit            'lazygit_{v}_Linux_x86_64.tar.gz'                                'lazygit'
register gh-dash        4.10.0  dlvhdr/gh-dash                   'gh-dash_{V}_linux_amd64.tar.gz'                                 'gh-dash'
register git-absorb     0.7.0   tummychow/git-absorb             'git-absorb-{V}-x86_64-unknown-linux-gnu.tar.gz'                 'git-absorb-{V}-x86_64-unknown-linux-gnu/git-absorb'
register git-branchless 0.10.0  arxanas/git-branchless           'git-branchless-{V}-x86_64-unknown-linux-gnu.tar.gz'             'git-branchless-{V}-x86_64-unknown-linux-gnu/git-branchless'
register git-who        0.9.0   sinclairtarget/git-who           'git-who_{V}_linux_amd64.tar.gz'                                 'git-who'
register spr            1.3.6   ejoffe/spr                       'spr_{v}_linux_amd64.tar.gz'                                     'spr'
register onefetch       2.24.0  o2sh/onefetch                    'onefetch-linux.tar.gz'                                          'onefetch'
register scc            3.4.0   boyter/scc                       'scc_Linux_x86_64.tar.gz'                                        'scc'
```

- [ ] **Step 2: Install the batch**

```bash
for t in lazygit gh-dash git-absorb git-branchless git-who spr onefetch scc; do
  bin/install-user-bins.sh "$t"
done
```

- [ ] **Step 3: Smoke test**

```bash
for t in lazygit gh-dash git-absorb git-branchless git-who spr onefetch scc; do
  "$HOME/.local/bin/$t" --version 2>/dev/null | head -1 || echo "$t: --version not supported (normal for some); file exists: $(ls -la $HOME/.local/bin/$t)"
done
```

- [ ] **Step 4: Lint + commit**

```bash
bin/lint-shell.sh
git add bin/install-user-bins.sh
git commit -m "install-user-bins: add git tooling (lazygit/gh-dash/git-absorb/branchless/who/spr/onefetch/scc)"
```

---

## Task 5 — Rest of the CLI set (btop, hyperfine, tealdeer, just, watchexec, asciinema, vhs, yazi, dust, duf, procs)

**Files:** Modify `bin/install-user-bins.sh`.

| tool | example | repo | asset pattern | bin inside |
|---|---|---|---|---|
| btop | 1.4.0 | aristocratos/btop | `btop-x86_64-linux-musl.tbz` | `btop/bin/btop` (special case — see below) |
| hyperfine | 1.19.0 | sharkdp/hyperfine | `hyperfine-{V}-x86_64-unknown-linux-gnu.tar.gz` | `hyperfine-{V}-x86_64-unknown-linux-gnu/hyperfine` |
| tealdeer (tldr) | 1.7.2 | tealdeer-rs/tealdeer | `tealdeer-linux-x86_64-musl` | `-` |
| just | 1.36.0 | casey/just | `just-{v}-x86_64-unknown-linux-musl.tar.gz` | `just` |
| watchexec | 2.3.0 | watchexec/watchexec | `watchexec-{v}-x86_64-unknown-linux-gnu.tar.xz` | `watchexec-{v}-x86_64-unknown-linux-gnu/watchexec` |
| asciinema | 2.4.0 | asciinema/asciinema | `asciinema-{v}-x86_64-unknown-linux-musl.tar.gz` | `asciinema-{v}-x86_64-unknown-linux-musl/asciinema` |
| vhs | 0.8.0 | charmbracelet/vhs | `vhs_{v}_Linux_x86_64.tar.gz` | `vhs_{v}_Linux_x86_64/vhs` |
| yazi | 0.4.0 | sxyazi/yazi | `yazi-x86_64-unknown-linux-gnu.zip` | `yazi-x86_64-unknown-linux-gnu/yazi` |
| dust | 1.2.0 | bootandy/dust | `dust-{V}-x86_64-unknown-linux-gnu.tar.gz` | `dust-{V}-x86_64-unknown-linux-gnu/dust` |
| duf | 0.8.1 | muesli/duf | `duf_{v}_linux_x86_64.tar.gz` | `duf` |
| procs | 0.14.8 | dalance/procs | `procs-v{v}-x86_64-linux.zip` | `procs` |

**btop edge case:** the archive uses `.tbz` (bzip2 tar). Extend the fetcher case-statement in `install-user-bins.sh` (§Task 1) to handle `*.tbz|*.tar.bz2 → tar xjf`.

- [ ] **Step 1: Extend the archive case-statement in `bin/install-user-bins.sh`**

Find:
```
    *.tar.xz)       tar xJf "$work/$asset" -C "$work"; src="$work/$bin_in_archive" ;;
```
Add before it:
```
    *.tar.bz2|*.tbz) tar xjf "$work/$asset" -C "$work"; src="$work/$bin_in_archive" ;;
```

- [ ] **Step 2: Add the rest of the registrations**

```bash
register btop        1.4.0   aristocratos/btop           'btop-x86_64-linux-musl.tbz'                                  'btop/bin/btop'
register hyperfine   1.19.0  sharkdp/hyperfine           'hyperfine-{V}-x86_64-unknown-linux-gnu.tar.gz'               'hyperfine-{V}-x86_64-unknown-linux-gnu/hyperfine'
register tldr        1.7.2   tealdeer-rs/tealdeer        'tealdeer-linux-x86_64-musl'                                  '-'
register just        1.36.0  casey/just                  'just-{v}-x86_64-unknown-linux-musl.tar.gz'                   'just'
register watchexec   2.3.0   watchexec/watchexec         'watchexec-{v}-x86_64-unknown-linux-gnu.tar.xz'               'watchexec-{v}-x86_64-unknown-linux-gnu/watchexec'
register asciinema   2.4.0   asciinema/asciinema         'asciinema-{v}-x86_64-unknown-linux-musl.tar.gz'              'asciinema-{v}-x86_64-unknown-linux-musl/asciinema'
register vhs         0.8.0   charmbracelet/vhs           'vhs_{v}_Linux_x86_64.tar.gz'                                 'vhs_{v}_Linux_x86_64/vhs'
register yazi        0.4.0   sxyazi/yazi                 'yazi-x86_64-unknown-linux-gnu.zip'                           'yazi-x86_64-unknown-linux-gnu/yazi'
register dust        1.2.0   bootandy/dust               'dust-{V}-x86_64-unknown-linux-gnu.tar.gz'                    'dust-{V}-x86_64-unknown-linux-gnu/dust'
register duf         0.8.1   muesli/duf                  'duf_{v}_linux_x86_64.tar.gz'                                 'duf'
register procs       0.14.8  dalance/procs               'procs-v{v}-x86_64-linux.zip'                                 'procs'
```

- [ ] **Step 3: Install**

```bash
for t in btop hyperfine tldr just watchexec asciinema vhs yazi dust duf procs; do
  bin/install-user-bins.sh "$t"
done
```

- [ ] **Step 4: Smoke test**

```bash
btop --version
hyperfine --version
tldr --version
just --version
watchexec --version
asciinema --version
vhs --version
yazi --version
dust --version
duf --version
procs --version
```

- [ ] **Step 5: Lint + commit**

```bash
bin/lint-shell.sh
git add bin/install-user-bins.sh
git commit -m "install-user-bins: add rest (btop/hyperfine/tldr/just/watchexec/asciinema/vhs/yazi/dust/duf/procs)"
```

---

## Task 6 — gh and yq (previously Tier A tdnf, now user-local)

**Files:** Modify `bin/install-user-bins.sh`.

| tool | example | repo | asset pattern | bin inside |
|---|---|---|---|---|
| gh | 2.63.2 | cli/cli | `gh_{v}_linux_amd64.tar.gz` | `gh_{v}_linux_amd64/bin/gh` |
| yq | 4.44.3 | mikefarah/yq | `yq_linux_amd64` | `-` |

- [ ] **Step 1: Edit `bin/install-user-bins.sh`**

```bash
register gh  2.63.2  cli/cli         'gh_{v}_linux_amd64.tar.gz'  'gh_{v}_linux_amd64/bin/gh'
register yq  4.44.3  mikefarah/yq    'yq_linux_amd64'             '-'
```

- [ ] **Step 2: Install + smoke test**

```bash
bin/install-user-bins.sh gh
bin/install-user-bins.sh yq
gh --version
yq --version
```

- [ ] **Step 3: Lint + commit**

```bash
bin/lint-shell.sh
git add bin/install-user-bins.sh
git commit -m "install-user-bins: add gh + yq"
```

---

## Task 7 — zsh via zsh-bin (special-case in install-user-bins.sh)

`zsh-bin` is not a GitHub release tarball — it's an installer script. Wire it in as a special-case dispatch inside `bin/install-user-bins.sh` so the unified installer remains the single entry point.

**Files:** Modify `bin/install-user-bins.sh`.

- [ ] **Step 1: Edit `bin/install-user-bins.sh` — add special-case function**

Before the `# --- dispatch ---` section, add:

```bash
install_zsh() {
  local target="$BINDIR/zsh"
  if (( ! FORCE )) && [[ -x "$target" ]]; then
    log "zsh $("$target" --version | awk '{print $2}') (already installed)"
    return 0
  fi
  log "installing zsh via romkatv/zsh-bin"
  # zsh-bin's installer is interactive by default; `-e no -d` makes it scripted.
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/master/install)" \
    -- -e no -d "$HOME/.local"
  "$target" --version
}

install_nvim() {
  # Pin a specific 0.10.x tag — verify at implementation time.
  local version="0.10.3"
  local target="$BINDIR/nvim"
  if (( ! FORCE )) && [[ -x "$target" ]]; then
    local current; current=$("$target" --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    if [[ "$current" == "$version" ]]; then
      log "nvim $version (already installed)"
      return 0
    fi
  fi
  log "installing nvim $version AppImage"
  local url="https://github.com/neovim/neovim/releases/download/v${version}/nvim-linux-x86_64.appimage"
  local tmp; tmp=$(mktemp -d); trap "rm -rf $tmp" RETURN
  curl -fsSL -o "$tmp/nvim.appimage" "$url"
  chmod +x "$tmp/nvim.appimage"
  # Try direct run (needs FUSE). Fall back to --appimage-extract if it fails.
  if "$tmp/nvim.appimage" --version >/dev/null 2>&1; then
    install -m755 "$tmp/nvim.appimage" "$target"
  else
    log "FUSE unavailable — extracting AppImage"
    (cd "$tmp" && ./nvim.appimage --appimage-extract >/dev/null)
    rm -rf "$BINDIR/../share/nvim-appimage"
    mkdir -p "$BINDIR/../share/nvim-appimage"
    cp -r "$tmp/squashfs-root/." "$BINDIR/../share/nvim-appimage/"
    ln -sfn "$BINDIR/../share/nvim-appimage/usr/bin/nvim" "$target"
  fi
  "$target" --version | head -1
}
```

Then in the `# --- dispatch ---` block, extend the loop body before the `install_tool "$t" …` line:

```bash
for t in "${tools[@]}"; do
  case "$t" in
    zsh)   install_zsh   || { failed=$((failed+1)); warn "zsh install FAILED"; }; continue ;;
    nvim)  install_nvim  || { failed=$((failed+1)); warn "nvim install FAILED"; }; continue ;;
  esac
  if [[ -z "${TOOL_VERSION[$t]:-}" ]]; then
    warn "unknown tool: $t"; failed=$((failed+1)); continue
  fi
  install_tool "$t" "${TOOL_VERSION[$t]}" "${TOOL_REPO[$t]}" "${TOOL_ASSET[$t]}" "${TOOL_BIN[$t]}" \
    || { failed=$((failed+1)); warn "$t install FAILED"; }
done
```

And extend the default-tools list so bare `install-user-bins.sh` (no args) includes zsh and nvim:

Find:
```
tools=("${!TOOL_VERSION[@]}")
```
Replace with:
```
tools=(zsh nvim "${!TOOL_VERSION[@]}")
```

- [ ] **Step 2: Install**

```bash
bin/install-user-bins.sh zsh
```

- [ ] **Step 3: Smoke test**

```bash
~/.local/bin/zsh --version     # expect zsh 5.9 or newer
~/.local/bin/zsh -c 'echo $ZSH_VERSION'
~/.local/bin/zsh -ic 'exit' && echo "interactive zsh OK"
```

- [ ] **Step 4: Lint + commit**

```bash
bin/lint-shell.sh
git add bin/install-user-bins.sh
git commit -m "install-user-bins: add zsh (via zsh-bin) + nvim (AppImage) special-cases"
```

---

## Task 8 — nvim AppImage install

Already coded in Task 7's `install_nvim()` function; this task installs + verifies.

**Files:** none new.

- [ ] **Step 1: Install**

```bash
bin/install-user-bins.sh nvim
```

- [ ] **Step 2: Smoke test**

```bash
~/.local/bin/nvim --version | head -3
# Expect: NVIM v0.10.x, LuaJIT ..., Build type: Release ...
~/.local/bin/nvim --headless +quit && echo "headless launch OK"
```

- [ ] **Step 3: No commit** (the install is already represented by Task 7's commit). This task is a verification gate.

---

## Task 9 — `shell/shared.sh` + `shell/bashrc` update

Cross-shell env file; both bash and zsh will source it.

**Files:**
- Create: `shell/shared.sh`
- Modify: `shell/bashrc` (source shared.sh at top)

- [ ] **Step 1: Write `shell/shared.sh`**

```bash
# shell/shared.sh — shell-agnostic env exports sourced by both bash and zsh.
# Keep this POSIX-compatible (no [[ ]], no arrays, no zsh-isms).

# PATH additions (idempotent — guard against duplicates)
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) export PATH="$HOME/bin:$PATH" ;;
esac

# Core env
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LESS="-FRSX"   # quit-if-one-screen, raw-control, chop-long, no-init
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# FZF
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --info=inline"

# bat as manpager (once bat is installed; guarded)
if command -v bat >/dev/null 2>&1; then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
```

- [ ] **Step 2: Update `shell/bashrc` to source shared.sh**

Prepend to `shell/bashrc` (after any existing shebang-ish comments, before any existing content):

```bash
# Source shell-agnostic env shared with zsh
if [ -f "$HOME/my_stuff/dotfiles/shell/shared.sh" ]; then
  . "$HOME/my_stuff/dotfiles/shell/shared.sh"
fi
```

Use a `sed` insert, since `shell/bashrc` already exists; use bash's existing `source` style (it's a bash-only file, so `source` is fine, but prefer `.` for POSIX compat).

- [ ] **Step 3: Verify bashrc still sources cleanly**

```bash
bash -ic 'echo $EDITOR'   # expect: nvim
bash -ic 'echo $PATH'     # expect: contains ~/.local/bin
```

- [ ] **Step 4: Lint + commit**

```bash
bin/lint-shell.sh
git add shell/shared.sh shell/bashrc
git commit -m "shell: add shared.sh for cross-shell env; bashrc sources it"
```

---

## Task 10 — `shell/zshenv`

Loaded by zsh on every invocation (interactive and non-interactive). Must be fast — source `shared.sh` only.

**Files:** Create `shell/zshenv`.

- [ ] **Step 1: Write `shell/zshenv`**

```zsh
# shell/zshenv — loaded for every zsh invocation (interactive + non-interactive).
# Keep this minimal: PATH + EDITOR only. Everything else belongs in zshrc.

# Source cross-shell env
if [[ -f "$HOME/my_stuff/dotfiles/shell/shared.sh" ]]; then
  source "$HOME/my_stuff/dotfiles/shell/shared.sh"
fi
```

- [ ] **Step 2: Symlink for manual smoke test**

```bash
ln -sfn "$PWD/shell/zshenv" "$HOME/.zshenv"
~/.local/bin/zsh -c 'echo "$EDITOR $PATH"'   # expect: nvim <PATH with ~/.local/bin>
```

- [ ] **Step 3: Commit**

```bash
git add shell/zshenv
git commit -m "shell: add zshenv (sources shared.sh for every zsh invocation)"
```

---

## Task 11 — `shell/zshrc` bootstrap

Interactive-only. Installs zinit on first run, sources every file under `~/.zshrc.d/*.zsh` in lex order.

**Files:** Create `shell/zshrc`.

- [ ] **Step 1: Write `shell/zshrc`**

```zsh
# shell/zshrc — interactive zsh config.
# Sourced after ~/.zshenv. Fast path: < 150 ms cold start (measured via
# `time zsh -ic exit`). Heavy work goes through zinit turbo (loads after
# first prompt).

# --- zinit bootstrap ---------------------------------------------------------
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
  print -P "%F{33}Installing zinit...%f"
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone --depth 1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "$ZINIT_HOME/zinit.zsh"

# --- turbo-loaded plugins (load AFTER first prompt) -------------------------
zinit wait lucid for \
  atinit"zicompinit; zicdreplay" \
    zdharma-continuum/fast-syntax-highlighting \
  atload"_zsh_autosuggest_start" \
    zsh-users/zsh-autosuggestions \
  blockf atpull'zinit creinstall -q .' \
    zsh-users/zsh-completions \
  Aloxaf/fzf-tab

# --- source modular config (~/.zshrc.d/*.zsh in lex order) ------------------
if [[ -d "$HOME/.zshrc.d" ]]; then
  for f in "$HOME/.zshrc.d"/*.zsh(N); do
    [[ -r "$f" ]] && source "$f"
  done
fi
```

- [ ] **Step 2: Symlink for smoke test**

```bash
ln -sfn "$PWD/shell/zshrc" "$HOME/.zshrc"
mkdir -p "$HOME/.zshrc.d"  # empty; will be symlinked to the repo dir in a later task
~/.local/bin/zsh -ic 'echo ready'
```

Expected: "Installing zinit..." on first run, then ready. Second run: no install message.

- [ ] **Step 3: Verify turbo loads (post-first-prompt check)**

```bash
~/.local/bin/zsh -ic 'zinit times | head'
```
Expected: autosuggestions, fast-syntax-highlighting, zsh-completions, fzf-tab all listed with load times.

- [ ] **Step 4: Commit**

```bash
git add shell/zshrc
git commit -m "shell: add zshrc bootstrap (zinit turbo + zshrc.d sourcing)"
```

---

## Task 12 — `shell/zshrc.d/00-path.zsh`, `10-env.zsh`, `20-history.zsh`, `30-opts.zsh`

Four foundation modules — deterministic behavior independent of any installed tool.

**Files:**
- Create: `shell/zshrc.d/00-path.zsh`
- Create: `shell/zshrc.d/10-env.zsh`
- Create: `shell/zshrc.d/20-history.zsh`
- Create: `shell/zshrc.d/30-opts.zsh`

- [ ] **Step 1: Write `00-path.zsh`**

```zsh
# 00-path.zsh — additional PATH entries (shared.sh handled the common ones).
# Nothing zsh-specific here yet; reserved for future additions.
```

- [ ] **Step 2: Write `10-env.zsh`**

```zsh
# 10-env.zsh — zsh-specific env only (cross-shell env lives in shell/shared.sh).
# Reserved; most env is in shared.sh to keep bash+zsh parity.
```

- [ ] **Step 3: Write `20-history.zsh`**

```zsh
# 20-history.zsh — zsh history settings.
# atuin takes over Ctrl-R below (75-atuin.zsh); this keeps the baseline
# plain-zsh history sane for up-arrow and non-atuin paths.

HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt APPEND_HISTORY            # multiple sessions append, not overwrite
setopt INC_APPEND_HISTORY        # incremental write (not just on exit)
setopt SHARE_HISTORY             # share new entries across running sessions
setopt HIST_IGNORE_DUPS          # don't record immediately-duplicated cmds
setopt HIST_IGNORE_ALL_DUPS      # remove older duplicates
setopt HIST_IGNORE_SPACE         # commands starting with space aren't saved
setopt HIST_REDUCE_BLANKS        # strip superfluous whitespace
setopt HIST_VERIFY               # don't exec !<hist> verbatim — confirm first
setopt EXTENDED_HISTORY          # timestamp + duration in history file
```

- [ ] **Step 4: Write `30-opts.zsh`**

```zsh
# 30-opts.zsh — zsh shell options.

setopt AUTO_CD                   # `dirname` alone -> cd dirname
setopt EXTENDED_GLOB             # ^ ~ # glob qualifiers on
setopt GLOB_DOTS                 # * matches dotfiles too
setopt INTERACTIVE_COMMENTS      # # in interactive commands
setopt LONG_LIST_JOBS            # full jobs output
setopt NO_BEEP                   # no beep on error
setopt NOTIFY                    # background job status reported immediately
setopt PROMPT_SUBST              # parameter expansion / arithmetic / cmdsub in prompt
setopt NUMERIC_GLOB_SORT         # `ls *.jpg` sorts numerically if applicable

# Vi mode (built-in, no plugin per spec §4.3)
bindkey -v
export KEYTIMEOUT=1              # 10ms escape-to-normal-mode delay
```

- [ ] **Step 5: Wire `~/.zshrc.d/` to the repo**

```bash
rm -rf "$HOME/.zshrc.d"
ln -sfn "$PWD/shell/zshrc.d" "$HOME/.zshrc.d"
~/.local/bin/zsh -ic 'echo options=$(setopt | wc -l)'
```

- [ ] **Step 6: Commit**

```bash
git add shell/zshrc.d/00-path.zsh shell/zshrc.d/10-env.zsh shell/zshrc.d/20-history.zsh shell/zshrc.d/30-opts.zsh
git commit -m "shell/zshrc.d: foundation modules (path/env/history/opts + vi mode)"
```

---

## Task 13 — `shell/zshrc.d/40-aliases.zsh`

**Files:** Create `shell/zshrc.d/40-aliases.zsh`.

- [ ] **Step 1: Write the file**

```zsh
# 40-aliases.zsh — aliases. Escape any with a leading backslash to reach the
# original command (e.g. \ls, \cat). `grep` is intentionally NOT aliased to rg
# per user preference — muscle-memory on unknown hosts.

# Claude / Copilot / kube (ported from bash)
alias c='claude'
alias cc='claude --continue'
alias cr='claude --resume'
alias cw='claude --worktree'
alias cp='copilot'
alias k='kubectl'

# Git
alias lg='lazygit'
alias gst='git status'
alias gd='git diff'
alias glg='git log --graph --oneline --all --decorate'
alias gfix='git absorb --and-rebase'
alias gdft='GIT_EXTERNAL_DIFF=difft git log -p --ext-diff'

# Modern CLI overrides (with \<cmd> escape to reach original)
alias ls='eza --icons'
alias ll='eza -lah --icons --git'
alias la='eza -a --icons'
alias lt='eza --tree --level=2 --icons'
alias cat='bat -p'

# Stats / inspection
alias clx='scc .'
alias dush='dust'
alias dfh='duf'
alias psh='procs'

# Recording
alias rec='asciinema rec'
```

- [ ] **Step 2: Smoke test**

```bash
~/.local/bin/zsh -ic 'alias ll; alias lg; alias c'
```
Expected: all three aliases printed.

- [ ] **Step 3: Commit**

```bash
git add shell/zshrc.d/40-aliases.zsh
git commit -m "shell/zshrc.d: add 40-aliases.zsh (git/modern-cli/claude/recording)"
```

---

## Task 14 — `shell/zshrc.d/50-modern-cli.zsh`

Environment for `eza`/`bat`/`fd`/`rg` — colors, pagers, config file paths. Each block is guarded by `command -v` so missing tools don't error.

**Files:** Create `shell/zshrc.d/50-modern-cli.zsh`.

- [ ] **Step 1: Write the file**

```zsh
# 50-modern-cli.zsh — tuning for bat/eza/fd/rg/delta.

# bat
if command -v bat >/dev/null; then
  export BAT_THEME="Catppuccin Mocha"
  export BAT_STYLE="numbers,changes,header"
fi

# eza — used via aliases; nothing to export here (icons inline via alias).

# fd — no env needed; honor .gitignore by default.

# ripgrep
if command -v rg >/dev/null; then
  export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
  [[ -f "$RIPGREP_CONFIG_PATH" ]] || {
    mkdir -p "$HOME/.config/ripgrep"
    cat > "$RIPGREP_CONFIG_PATH" <<'EOF'
--smart-case
--max-columns=200
--glob=!.git/*
--glob=!*.lock
EOF
  }
fi

# delta — honored by git via git/gitconfig (no env needed).
```

- [ ] **Step 2: Commit**

```bash
git add shell/zshrc.d/50-modern-cli.zsh
git commit -m "shell/zshrc.d: add 50-modern-cli.zsh (bat/rg config)"
```

---

## Task 15 — `shell/zshrc.d/60-fzf.zsh` + key bindings

**Files:** Create `shell/zshrc.d/60-fzf.zsh`.

- [ ] **Step 1: Write the file**

```zsh
# 60-fzf.zsh — fzf key bindings + completion.
# Ctrl-T: file picker. Alt-C: cd. Ctrl-R: handled by atuin (75-atuin.zsh).

if command -v fzf >/dev/null; then
  # fzf ships key bindings + completion scripts inside its repo. We source
  # the ones that shipped with the binary's release tarball (if present).
  for _fzf_src in \
    "$HOME/.local/share/fzf/key-bindings.zsh" \
    "$HOME/.fzf/shell/key-bindings.zsh"; do
    [[ -f "$_fzf_src" ]] && source "$_fzf_src" && break
  done
  for _fzf_comp in \
    "$HOME/.local/share/fzf/completion.zsh" \
    "$HOME/.fzf/shell/completion.zsh"; do
    [[ -f "$_fzf_comp" ]] && source "$_fzf_comp" && break
  done

  # Prefer fd for listings (faster, gitignore-aware)
  if command -v fd >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
  fi
fi
```

Note: the fzf key-binding + completion shell files ship inside the release tarball at `shell/*.zsh`. The `install-user-bins.sh` fetcher extracts only the `fzf` binary. Add a post-install hook:

- [ ] **Step 2: Extend `bin/install-user-bins.sh` to extract fzf's shell integrations**

Add a post-install override for `fzf`. After the generic `install_tool` returns, add in the dispatch loop:

```bash
  install_tool "$t" "${TOOL_VERSION[$t]}" "${TOOL_REPO[$t]}" "${TOOL_ASSET[$t]}" "${TOOL_BIN[$t]}" \
    || { failed=$((failed+1)); warn "$t install FAILED"; continue; }
  case "$t" in
    fzf)
      # Re-fetch the tarball to extract the shell integration scripts.
      local v="${TOOL_VERSION[$t]}"
      local asset="fzf-${v}-linux_amd64.tar.gz"
      # The shell/ dir is NOT in the release tarball (fzf ships binary only).
      # Clone the fzf repo at that tag just for shell/.
      local dest="$HOME/.local/share/fzf"
      mkdir -p "$dest"
      curl -fsSL "https://raw.githubusercontent.com/junegunn/fzf/v${v}/shell/key-bindings.zsh" \
        -o "$dest/key-bindings.zsh"
      curl -fsSL "https://raw.githubusercontent.com/junegunn/fzf/v${v}/shell/completion.zsh" \
        -o "$dest/completion.zsh"
      log "fzf shell integration installed at $dest"
      ;;
  esac
```

- [ ] **Step 3: Re-install fzf to fetch the integration files**

```bash
bin/install-user-bins.sh --force fzf
ls -la "$HOME/.local/share/fzf/"
```

- [ ] **Step 4: Verify Ctrl-T binding works interactively** (manual — user types Ctrl-T in a zsh shell and sees fzf popup).

- [ ] **Step 5: Lint + commit**

```bash
bin/lint-shell.sh
git add shell/zshrc.d/60-fzf.zsh bin/install-user-bins.sh
git commit -m "shell/zshrc.d: add 60-fzf.zsh; install-user-bins fetches fzf shell integration"
```

---

## Task 16 — Remaining zshrc.d init-evals (70-zoxide, 75-atuin, 80-direnv, 85-carapace, 90-starship)

**Files:**
- Create: `shell/zshrc.d/70-zoxide.zsh`
- Create: `shell/zshrc.d/75-atuin.zsh`
- Create: `shell/zshrc.d/80-direnv.zsh`
- Create: `shell/zshrc.d/85-carapace.zsh`
- Create: `shell/zshrc.d/90-starship.zsh`

- [ ] **Step 1: Write `70-zoxide.zsh`**

```zsh
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
fi
```

- [ ] **Step 2: Write `75-atuin.zsh`**

```zsh
if command -v atuin >/dev/null; then
  eval "$(atuin init zsh --disable-up-arrow)"
fi
```

- [ ] **Step 3: Write `80-direnv.zsh`**

```zsh
if command -v direnv >/dev/null; then
  eval "$(direnv hook zsh)"
fi
```

- [ ] **Step 4: Write `85-carapace.zsh`**

```zsh
if command -v carapace >/dev/null; then
  export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
  zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
  source <(carapace _carapace zsh)
fi
```

- [ ] **Step 5: Write `90-starship.zsh`**

```zsh
if command -v starship >/dev/null; then
  eval "$(starship init zsh)"
fi
```

- [ ] **Step 6: Smoke test all inits**

```bash
~/.local/bin/zsh -ic '
  type _zoxide_hook >/dev/null && echo zoxide: ok
  type _atuin_postexec >/dev/null && echo atuin: ok
  type __direnv_hook >/dev/null && echo direnv: ok
  type _carapace >/dev/null && echo carapace: ok
  type prompt_starship_precmd >/dev/null && echo starship: ok
'
```
Expected: all five lines print "ok".

- [ ] **Step 7: Commit**

```bash
git add shell/zshrc.d/70-zoxide.zsh shell/zshrc.d/75-atuin.zsh shell/zshrc.d/80-direnv.zsh shell/zshrc.d/85-carapace.zsh shell/zshrc.d/90-starship.zsh
git commit -m "shell/zshrc.d: add eval-init modules (zoxide/atuin/direnv/carapace/starship)"
```

---

## Task 17 — `config/atuin/config.toml` for cloud sync

**Files:** Create `config/atuin/config.toml`.

- [ ] **Step 1: Write the config**

```toml
# ~/.config/atuin/config.toml
# Managed via dotfiles. `atuin register` / `atuin login` run once per host;
# no credentials committed here.

auto_sync = true
sync_frequency = "5m"
sync_address = "https://api.atuin.sh"

update_check = false

filter_mode_shell_up_key = "session"
search_mode = "fuzzy"
dialect = "us"
style = "compact"
show_preview = true
inline_height = 20

[keys]
exit_past_line_start = true
```

- [ ] **Step 2: Commit**

```bash
git add config/atuin/config.toml
git commit -m "Add config/atuin/config.toml (cloud sync + Ctrl-R rewire)"
```

---

## Task 18 — `config/starship.toml` — tune to two-line + git modules on

The file already exists from observability phase (linked by install.sh). Confirm + tune.

**Files:** Modify `config/starship.toml`.

- [ ] **Step 1: Read current contents**

```bash
cat config/starship.toml
```

- [ ] **Step 2: Replace with the finalised config**

```toml
# config/starship.toml — two-line prompt per spec §4.6.
# Modules ON: directory, git_branch, git_commit, git_state, git_status,
#             cmd_duration, status, jobs, character.
# Modules OFF: hostname, username, time, battery, package, language prompts.

format = """
$directory\
$git_branch\
$git_commit\
$git_state\
$git_status\
$cmd_duration\
$status\
$jobs
$character"""

scan_timeout = 10
command_timeout = 300

[directory]
truncation_length = 3
truncation_symbol = "…/"
style = "bold cyan"

[git_branch]
symbol = " "
style = "bold purple"

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "bold yellow"
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕⇡${ahead_count}⇣${behind_count}"
conflicted = "="
untracked = "?"
modified = "*"
staged = "+"

[git_state]
format = '\(🔀 $state( $progress_current/$progress_total)\) '
style = "bold red"

[cmd_duration]
min_time = 2_000
format = '[took $duration](bold yellow) '

[status]
disabled = false
format = '[$symbol]($style) '
symbol = "✗"
success_symbol = ""
style = "bold red"

[jobs]
symbol = "&"
style = "bold blue"
number_threshold = 1

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
vimcmd_symbol = "[❮](bold green)"

# Explicitly OFF
[hostname]
disabled = true
[username]
disabled = true
[time]
disabled = true
[battery]
disabled = true
[package]
disabled = true
[python]
disabled = true
[nodejs]
disabled = true
[rust]
disabled = true
[golang]
disabled = true
```

- [ ] **Step 3: Smoke test**

```bash
~/.local/bin/zsh -ic 'starship prompt || true' | head -5
```

- [ ] **Step 4: Commit**

```bash
git add config/starship.toml
git commit -m "starship: two-line prompt with git modules on; disable language prompts"
```

---

## Task 19 — tmux shell swap to zsh

**Files:** Modify `tmux/tmux.conf.local.tpl`.

- [ ] **Step 1: Edit the file**

Locate:
```
set -g default-command "exec /bin/bash --login"
set -g default-shell "/bin/bash"
```

Replace with:
```
# zsh via zsh-bin (see docs/superpowers/specs/2026-04-21-productivity-design.md §4.1)
set -g default-command "exec __HOME__/.local/bin/zsh --login"
set -g default-shell "__HOME__/.local/bin/zsh"
```

- [ ] **Step 2: Regenerate the live file + reload**

```bash
sed "s|__USER__|$USER|g; s|__HOME__|$HOME|g" tmux/tmux.conf.local.tpl > "$HOME/.tmux.conf.local"
tmux source ~/.tmux.conf
```

- [ ] **Step 3: Smoke test — new tmux pane should open zsh**

```bash
# From inside an existing tmux session:
tmux new-window -n zsh-test
# Then, in that window:
echo "$SHELL"          # expect: /home/spopuri/.local/bin/zsh
ps -p $$ -o comm=      # expect: zsh
tmux kill-window
```

- [ ] **Step 4: Commit**

```bash
git add tmux/tmux.conf.local.tpl
git commit -m "tmux: swap default-command + default-shell to zsh (~/.local/bin/zsh)"
```

---

## Task 20 — Cold-start budget verification

**Files:** none new (verification only).

- [ ] **Step 1: Measure cold start**

```bash
# Prime then re-time cold (invalidate compinit cache)
rm -f "$HOME/.zcompdump"* 2>/dev/null
hyperfine -w 2 -m 10 '~/.local/bin/zsh -ic exit'
```

- [ ] **Step 2: Budget check**

Expected: mean < **150 ms** (target per spec §8.3). If over:

- Inspect: `~/.local/bin/zsh -ic 'zinit times'` — any non-turbo plugin loading synchronously?
- Inspect: `~/.local/bin/zsh -ic 'zmodload -F zsh/zprof +zsh/zprof; zprof | head -30'` — which init-eval is slow?
- Typical fixes: drop an unused init, move a plugin behind `wait`, defer `compinit` rebuilds.

- [ ] **Step 3: If within budget, no commit needed.** If fixes were required, commit each with a clear message.

---

## Task 21 — NvChad at `config/nvim/`

Clone the NvChad starter into the repo; commit the snapshot; user overrides go under `config/nvim/lua/custom/`.

**Files:**
- Create: `config/nvim/` (cloned snapshot — many files)
- Create: `config/nvim/lua/custom/chadrc.lua`
- Create: `config/nvim/lua/custom/plugins.lua`
- Create: `config/nvim/lua/custom/mappings.lua`

- [ ] **Step 1: Clone the starter into the repo**

```bash
# Clone to a throwaway location, copy the contents in (without the upstream .git),
# so the dotfiles repo owns the history going forward.
rm -rf /tmp/nvchad-starter
git clone --depth 1 https://github.com/NvChad/starter /tmp/nvchad-starter
rm -rf /tmp/nvchad-starter/.git
mkdir -p config/nvim
cp -a /tmp/nvchad-starter/. config/nvim/
rm -rf /tmp/nvchad-starter
```

- [ ] **Step 2: Write `config/nvim/lua/custom/chadrc.lua`**

```lua
-- Custom NvChad config overrides.
-- See https://nvchad.com/docs/config/theme for reference.

---@type ChadrcConfig
local M = {}

M.ui = {
  theme = "catppuccin",
  theme_toggle = { "catppuccin", "chadracula" },
  transparency = false,
  hl_override = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
  },
}

M.plugins = "custom.plugins"
M.mappings = require "custom.mappings"

return M
```

- [ ] **Step 3: Write `config/nvim/lua/custom/plugins.lua`**

```lua
-- User-added plugins on top of NvChad defaults.
local plugins = {
  { "catppuccin/nvim", name = "catppuccin" },
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = { current_line_blame = false },
  },
  {
    "kdheepak/lazygit.nvim",
    cmd = { "LazyGit", "LazyGitCurrentFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
  },
  { "stevearc/oil.nvim", opts = {} },
  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    opts = { use_diagnostic_signs = true },
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
    },
  },
  { "kylechui/nvim-surround", event = "VeryLazy", opts = {} },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "lua-language-server", "pyright", "rust-analyzer", "gopls",
        "bash-language-server", "yaml-language-server", "json-lsp",
        "marksman",
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua", "python", "rust", "go", "bash", "yaml", "json",
        "markdown", "markdown_inline", "toml", "tmux", "gitcommit",
        "diff", "dockerfile", "make", "regex", "vim", "vimdoc",
      },
    },
  },
}
return plugins
```

- [ ] **Step 4: Write `config/nvim/lua/custom/mappings.lua`**

```lua
-- Extra keymaps (NvChad uses which-key for discoverability).
local M = {}

M.general = {
  n = {
    ["<leader>ff"] = { "<cmd>Telescope find_files<cr>", "Find files" },
    ["<leader>fg"] = { "<cmd>Telescope live_grep<cr>", "Live grep" },
    ["<leader>fb"] = { "<cmd>Telescope buffers<cr>", "Buffers" },
    ["<leader>fk"] = { "<cmd>Telescope keymaps<cr>", "Keymaps" },
    ["<leader>gg"] = { "<cmd>LazyGit<cr>", "Lazygit" },
    ["<leader>gs"] = { "<cmd>Gitsigns toggle_current_line_blame<cr>", "Git blame toggle" },
    ["<leader>gd"] = { "<cmd>Gitsigns preview_hunk<cr>", "Git preview hunk" },
    ["<leader>xx"] = { "<cmd>Trouble diagnostics toggle<cr>", "Trouble diagnostics" },
    ["<leader>e"]  = { "<cmd>Oil --float<cr>", "File manager" },
  },
}

return M
```

- [ ] **Step 5: Symlink + smoke test**

```bash
mkdir -p "$HOME/.config"
rm -rf "$HOME/.config/nvim"
ln -sfn "$PWD/config/nvim" "$HOME/.config/nvim"
# First launch installs plugins — let it run headless for determinism.
timeout 300 ~/.local/bin/nvim --headless "+Lazy! sync" "+qa!" 2>&1 | tail -20
# Then interactively open to verify it comes up (manual).
# ~/.local/bin/nvim
```

- [ ] **Step 6: Commit**

```bash
git add config/nvim/
git commit -m "Add NvChad at config/nvim/ with catppuccin + LSP/treesitter + gitsigns/lazygit"
```

---

## Task 22 — LazyVim at `config/nvim-lazy/`

**Files:**
- Create: `config/nvim-lazy/` (cloned snapshot)
- Create: `config/nvim-lazy/lua/plugins/user.lua`
- Alias: `lv='NVIM_APPNAME=nvim-lazy nvim'` (added to 40-aliases.zsh in a follow-up commit).

- [ ] **Step 1: Clone the LazyVim starter**

```bash
rm -rf /tmp/lazyvim-starter
git clone --depth 1 https://github.com/LazyVim/starter /tmp/lazyvim-starter
rm -rf /tmp/lazyvim-starter/.git
mkdir -p config/nvim-lazy
cp -a /tmp/lazyvim-starter/. config/nvim-lazy/
rm -rf /tmp/lazyvim-starter
```

- [ ] **Step 2: Write `config/nvim-lazy/lua/plugins/user.lua`**

```lua
-- User overrides on top of LazyVim defaults.
return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
  { "catppuccin/nvim", name = "catppuccin" },
  {
    "kdheepak/lazygit.nvim",
    cmd = { "LazyGit", "LazyGitCurrentFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<cr>", desc = "Lazygit" },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua", "python", "rust", "go", "bash", "yaml", "json",
        "markdown", "markdown_inline", "toml", "tmux", "gitcommit",
        "diff", "dockerfile", "make", "regex", "vim", "vimdoc",
      },
    },
  },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "pyright", "rust-analyzer", "gopls", "lua-language-server",
        "bash-language-server", "yaml-language-server", "json-lsp",
        "marksman",
      },
    },
  },
}
```

- [ ] **Step 3: Symlink + smoke test**

```bash
rm -rf "$HOME/.config/nvim-lazy"
ln -sfn "$PWD/config/nvim-lazy" "$HOME/.config/nvim-lazy"
timeout 300 env NVIM_APPNAME=nvim-lazy ~/.local/bin/nvim --headless "+Lazy! sync" "+qa!" 2>&1 | tail -20
```

- [ ] **Step 4: Add `lv` alias**

Append to `shell/zshrc.d/40-aliases.zsh` (from Task 13):

```zsh
# LazyVim (via NVIM_APPNAME for isolation)
alias lv='NVIM_APPNAME=nvim-lazy nvim'
```

- [ ] **Step 5: Smoke test the alias**

```bash
~/.local/bin/zsh -ic 'alias lv; which lv'
```

- [ ] **Step 6: Commit**

```bash
git add config/nvim-lazy/ shell/zshrc.d/40-aliases.zsh
git commit -m "Add LazyVim at config/nvim-lazy/ + lv alias (NVIM_APPNAME isolation)"
```

---

## Task 23 — `install.sh` orchestration

**Files:** Modify `install.sh`.

- [ ] **Step 1: Add the zsh dotfile symlinks + atuin config + nvim configs + user-bins invocation**

Insert into `install.sh` (between the existing Shell and Vim blocks — adapt to where `link` / `generate` helpers are already used):

```bash
echo "=== Zsh ==="
link "$DOTFILES/shell/zshenv"  "$HOME/.zshenv"
link "$DOTFILES/shell/zshrc"   "$HOME/.zshrc"
rm -f "$HOME/.zshrc.d" 2>/dev/null
ln -sfn "$DOTFILES/shell/zshrc.d" "$HOME/.zshrc.d"

echo "=== Atuin ==="
mkdir -p "$HOME/.config/atuin"
link "$DOTFILES/config/atuin/config.toml" "$HOME/.config/atuin/config.toml"

echo "=== Neovim ==="
mkdir -p "$HOME/.config"
rm -rf "$HOME/.config/nvim" 2>/dev/null
ln -sfn "$DOTFILES/config/nvim"      "$HOME/.config/nvim"
rm -rf "$HOME/.config/nvim-lazy" 2>/dev/null
ln -sfn "$DOTFILES/config/nvim-lazy" "$HOME/.config/nvim-lazy"

echo "=== User-local binaries ==="
bash "$DOTFILES/bin/install-user-bins.sh"
```

- [ ] **Step 2: Re-run install.sh**

```bash
bash install.sh
```
Expected: all Zsh / Atuin / Neovim / User-local sections pass; install-user-bins reports "already installed" for most tools, zsh and nvim too (already installed via earlier tasks).

- [ ] **Step 3: Commit**

```bash
git add install.sh
git commit -m "install.sh: wire Zsh, Atuin, Neovim (both distros), install-user-bins"
```

---

## Task 24 — `sync.sh` BIN_SCRIPTS catch-up

**Files:** Modify `sync.sh`.

- [ ] **Step 1: Ensure every new script is in `BIN_SCRIPTS`**

Only `install-user-bins.sh` was added (Task 1). Verify:
```bash
grep BIN_SCRIPTS= sync.sh
```
Expected: the array includes `install-user-bins.sh`. If not, add it.

- [ ] **Step 2: Commit if changed** (no commit if already up-to-date).

---

## Task 25 — README — Productivity phase section

**Files:** Modify `README.md`.

- [ ] **Step 1: Append a "Productivity (power-productivity phase)" section** at the bottom of README.md:

```markdown
## Productivity (power-productivity phase)

### Shell
- Interactive shell in tmux: **zsh** (installed via `romkatv/zsh-bin` to `~/.local/bin/zsh`, no sudo).
- Login shell: unchanged (bash).
- Plugin manager: **zinit** (turbo-mode). Config under `shell/zshrc` + modular `shell/zshrc.d/*.zsh`.
- Turbo-loaded plugins: `zsh-autosuggestions`, `fast-syntax-highlighting`, `zsh-completions`, `fzf-tab`.
- Completion layers: zsh builtins → zsh-completions → tool-native → `bashcompinit` → **carapace-bin**.
- Eval-init: `starship`, `zoxide`, `atuin`, `direnv`, `carapace`.
- Cold start target: `time zsh -ic exit` < 150 ms.

### CLI tools (one-shot install)
`bin/install-user-bins.sh` installs ~30 static binaries into `~/.local/bin/`:
atuin, bat, btop, carapace-bin, delta, difft, duf, dust, eza, fd, fzf,
gh, gh-dash, git-absorb, git-branchless, git-who, hyperfine, jq, just,
lazygit, onefetch, procs, rg, scc, sd, spr, starship, tldr, vhs,
watchexec, yazi, zoxide, direnv, asciinema, yq, zsh, nvim.
Idempotent; `--force` to re-install.

### Neovim
Two distros coexist via `NVIM_APPNAME`:
- `nvim` → **NvChad** (default). Config at `config/nvim/`.
- `lv` → **LazyVim** (fallback). Config at `config/nvim-lazy/`.

Both get: catppuccin theme, LSP (pyright, rust-analyzer, gopls, lua_ls, bashls,
yamlls, jsonls, marksman), treesitter, telescope, gitsigns, lazygit.nvim, oil,
which-key, trouble.

Key bindings (leader = `<space>`): `<leader>ff` files, `<leader>fg` grep,
`<leader>gg` lazygit, `<leader>e` oil file manager, `<leader>xx` trouble.

### Atuin cloud sync

```bash
atuin register -u <username> -e <email>   # first host only
atuin login -u <username>                  # each subsequent host
atuin sync
```

### Spec / plan / user guide
- Spec: `docs/superpowers/specs/2026-04-21-productivity-design.md`
- Plan: `docs/superpowers/plans/2026-04-21-productivity.md`
- User guide: `docs/guides/2026-04-21-productivity-user-guide.md`
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "README: add Productivity phase section"
```

---

## Task 26 — CLAUDE.md — Key Scripts refresh

**Files:** Modify `CLAUDE.md`.

- [ ] **Step 1: Add rows for new scripts** in the Key Scripts table:

```
| `bin/install-user-bins.sh` | Unified idempotent installer for all user-local CLI binaries (zsh via zsh-bin, nvim AppImage, ~30 Rust/Go binaries). No tdnf, no sudo. Version-pinned. |
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "CLAUDE.md: add install-user-bins.sh row to Key Scripts"
```

---

## Task 27 — env.txt regenerate

**Files:** Modify `env.txt`.

- [ ] **Step 1: Regenerate**

```bash
{
  echo "# env.txt — inventory snapshot"
  echo "# Generated: $(date -u +%Y-%m-%dT%H:%MZ) on $(hostname -s)"
  echo
  echo "## OS"
  cat /etc/os-release 2>/dev/null
  echo
  echo "## Kernel"
  uname -a
  echo
  echo "## Interactive shell (tmux default)"
  ~/.local/bin/zsh --version
  echo
  echo "## Neovim"
  ~/.local/bin/nvim --version | head -3
  echo
  echo "## Tools in ~/.local/bin/"
  ls -1 "$HOME/.local/bin/"
  echo
  echo "## Key tools (command -v probes)"
  for t in tmux bash zsh git git-lfs age jq shellcheck bats gh yq \
           nvim atuin bat btop carapace delta difft duf dust eza fd fzf \
           gh-dash git-absorb git-branchless git-who hyperfine just \
           lazygit onefetch procs rg scc sd spr starship tldr vhs \
           watchexec yazi zoxide direnv asciinema; do
    p=$(command -v "$t" 2>/dev/null || true)
    printf '  %-20s %s\n' "$t" "${p:-(missing)}"
  done
} > env.txt
```

- [ ] **Step 2: Commit**

```bash
git add env.txt
git commit -m "env.txt: regenerate with zsh/nvim/full Tier-B inventory"
```

---

## Task 28 — CHANGELOG — Productivity phase entry

**Files:** Modify `CHANGELOG.md`.

- [ ] **Step 1: Prepend** a new block at the top (after `# Changelog`):

```markdown
## 2026-04-21 — Productivity phase (branch: power-productivity)

Second phase of the power-tui overhaul — shell + CLI + neovim. Per
`docs/superpowers/specs/2026-04-21-productivity-design.md` and its plan.

**Shell stack:**
- zsh installed via `romkatv/zsh-bin` to `~/.local/bin/zsh` (no tdnf, no sudo,
  no build toolchain).
- tmux default-command + default-shell flipped to `~/.local/bin/zsh`. Login
  shell unchanged (bash).
- Plugin manager: **zinit** (turbo-mode). Cold-start target < 150 ms.
- Modular `~/.zshrc.d/00-path.zsh … 90-starship.zsh`.
- Turbo plugins: `zsh-autosuggestions`, `fast-syntax-highlighting`,
  `zsh-completions`, `fzf-tab`. `zsh-vi-mode` deliberately NOT installed
  (built-in zsh vi-mode is enough).
- Eval-init: starship, atuin (cloud sync), zoxide, direnv, carapace-bin.
- Completion layering: builtins → zsh-completions → tool-native → bashcompinit
  bridge → carapace-bin.

**CLI binaries** (all via `bin/install-user-bins.sh`, user-local to
`~/.local/bin/`, no tdnf): gh, yq, atuin, bat, btop, carapace-bin, delta,
difft, duf, dust, eza, fd, fzf, gh-dash, git-absorb, git-branchless, git-who,
hyperfine, jq, just, lazygit, onefetch, procs, rg, scc, sd, spr, starship,
tldr, vhs, watchexec, yazi, zoxide, direnv, asciinema.

**Neovim:** NvChad at `nvim` (config at `config/nvim/`) + LazyVim at `lv`
(config at `config/nvim-lazy/`) via `NVIM_APPNAME` isolation.

**Configs:** `config/atuin/config.toml`, `config/starship.toml` (tuned),
`config/nvim/lua/custom/*.lua` (NvChad overrides), `config/nvim-lazy/lua/plugins/user.lua`
(LazyVim overrides).

**No tdnf calls anywhere in this phase** — every binary lands via
`install-user-bins.sh` from upstream GitHub releases.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "CHANGELOG: Productivity phase entry"
```

---

## Task 29 — User guide (FINALE)

**Files:** Create `docs/guides/2026-04-21-productivity-user-guide.md`.

- [ ] **Step 1: Write the guide**

```markdown
# Productivity — User Guide

Covers the second-phase power-tui additions: zsh as tmux shell, ~30 CLI
tools in `~/.local/bin/`, and two neovim distros (NvChad default, LazyVim
fallback).

Design rationale: `docs/superpowers/specs/2026-04-21-productivity-design.md`.
Implementation history: `docs/superpowers/plans/2026-04-21-productivity.md`.

---

## First time on this host

```bash
cd ~/my_stuff/dotfiles
./bin/install-user-bins.sh       # installs zsh + nvim + ~30 tools (~5 min)
./install.sh                      # symlinks everything into place

# Atuin cloud sync — interactive, run once per host:
atuin register -u <user> -e <email>   # only on the FIRST host ever
atuin login -u <user>                  # on subsequent hosts
atuin sync
```

Open a new tmux pane → you're in zsh with starship two-line prompt.

## Shell

- Interactive shell in tmux: **zsh** (at `~/.local/bin/zsh`).
- Shell outside tmux (SSH direct, cron, scripts): **bash** (unchanged).
- `~/.zshrc` → `dotfiles/shell/zshrc`; modules under `~/.zshrc.d/` (symlink
  to `dotfiles/shell/zshrc.d/`).
- Cold start target: `time zsh -ic exit` < 150 ms.

### Key bindings

| Key | Action |
|---|---|
| `Ctrl-R` | atuin history (cross-host via cloud sync) |
| `Ctrl-T` | fzf file picker |
| `Alt-C` | fzf cd |
| `z <dir>` | zoxide smart-cd (fuzzy, frecency-ranked) |
| `zi` | zoxide interactive fzf picker |
| `Esc` then `v` | open current command in `$EDITOR` (vi mode) |

### Aliases

Claude / Copilot:
- `c` / `cc` / `cr` / `cw` — claude / --continue / --resume / --worktree
- `cp` — copilot

Git:
- `lg` — lazygit
- `gst` — git status
- `glg` — git log graph
- `gfix` — `git absorb --and-rebase`
- `gdft` — difftastic log
- `gd` — git diff

Modern CLI (escape via `\ls`, `\cat` to reach originals):
- `ls` → eza --icons
- `ll` → eza -lah --icons --git
- `la` / `lt` — eza variants
- `cat` → bat -p

Misc: `clx` (scc .), `dush`, `dfh`, `psh`, `rec` (asciinema rec).

**`grep` is deliberately NOT aliased** — preserves muscle memory on
unfamiliar hosts. `rg` is a separate command.

## CLI tools (in `~/.local/bin/`)

**Install / update:**
```bash
bin/install-user-bins.sh          # install missing, upgrade outdated
bin/install-user-bins.sh --force  # re-install every tool
bin/install-user-bins.sh <name>   # install a single tool
```

**Tools** (grouped):
- Shell UX: atuin · zoxide · starship · direnv · carapace-bin · fzf
- Core CLI replacements: bat · eza · fd · rg · delta · difft · sd · jq
- Git tooling: lazygit · gh-dash · git-absorb · git-branchless · git-who · spr · onefetch · scc
- System: btop · hyperfine · tldr · just · watchexec · asciinema · vhs · yazi · dust · duf · procs
- Bridges: gh · yq

**Version policy:** pins in the `TOOLS` table are concrete semvers — bump
quarterly via `git diff`. `bin/install-user-bins.sh --check-latest` is a
future helper that compares pins to upstream.

## Neovim

Two distros, both installed, both isolated via `NVIM_APPNAME`:

| Command | Distro | Config dir | Data dir |
|---|---|---|---|
| `nvim` | NvChad (default) | `~/.config/nvim/` | `~/.local/share/nvim/` |
| `lv` | LazyVim (fallback) | `~/.config/nvim-lazy/` | `~/.local/share/nvim-lazy/` |

### First launch (each distro)

`nvim` or `lv` — the respective plugin manager (NvChad's built-in / lazy.nvim)
fetches its plugin tree on first open. ~15-30 seconds. Subsequent launches
~100 ms.

### Keymaps (both distros)

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

## Troubleshooting

### "zsh: command not found" in tmux

Re-run `bin/install-user-bins.sh zsh` and verify `tmux show -g default-shell`
points at `$HOME/.local/bin/zsh`. Then `tmux source ~/.tmux.conf` and open
a fresh pane.

### Shell start feels slow

```bash
hyperfine -m 10 '~/.local/bin/zsh -ic exit'
~/.local/bin/zsh -ic 'zmodload -F zsh/zprof +zsh/zprof; zprof | head -30'
~/.local/bin/zsh -ic 'zinit times'
```

Typical culprits: a non-turbo plugin syncing at startup, `compinit` rebuild,
slow eval-init (run `starship explain` to see per-module cost).

### atuin isn't syncing between ld4 and ld5

```bash
atuin status        # shows local-only vs cloud status
atuin sync --force  # push/pull now
cat ~/.config/atuin/config.toml | grep sync_
```

If `auto_sync = false` or `sync_address` missing: config symlink is broken.
Re-run `./install.sh`.

### `nvim` crashes on launch / plugins fail to install

```bash
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim
nvim --headless "+Lazy! sync" "+qa!"
```

For LazyVim (`lv`), substitute `nvim-lazy` everywhere.

### Tool not found even after install

```bash
echo $PATH | tr ':' '\n' | grep local
ls -l ~/.local/bin/<tool>
```

If ~/.local/bin missing from PATH: re-source `shell/shared.sh` (added to
both bash and zsh): `source ~/my_stuff/dotfiles/shell/shared.sh`.

### Carapace completions interfere with a specific command

Disable carapace for that command:
```bash
CARAPACE_BRIDGES='' carapace --export | less
# Or in zshrc.d/85-carapace.zsh: export CARAPACE_HIDDEN=<cmd>,<cmd>
```

### `ls` (eza) output too busy on pipes

The alias is only applied for interactive shells. Pipes get the real `ls`:
```bash
\ls /var/log | head
ls --help      # still goes to eza via alias (use command ls for alt)
```

## Rollback

### Revert to bash as tmux default

Edit `tmux/tmux.conf.local.tpl`, restore:
```
set -g default-command "exec /bin/bash --login"
set -g default-shell "/bin/bash"
```
Then `tmux source ~/.tmux.conf`.

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
git log --oneline | grep -E 'productivity|zsh|zshrc|nvim' | head
git revert <squash-commit-sha>
./install.sh       # re-symlinks, which will now drop the zsh/nvim links
```

## Cross-reference

- Spec: `docs/superpowers/specs/2026-04-21-productivity-design.md`
- Plan: `docs/superpowers/plans/2026-04-21-productivity.md`
- Observability phase (pre-requisite): `docs/guides/2026-04-19-observability-user-guide.md`
```

- [ ] **Step 2: Commit**

```bash
git add docs/guides/2026-04-21-productivity-user-guide.md
git commit -m "docs: write productivity user guide (final deliverable)"
```

---

## Post-implementation verification

Run through the spec's §8 acceptance criteria (items 1–20). Any failures → follow-up commits on `power-productivity`. When all pass, the phase is ready to squash-merge:

```bash
git checkout master
git merge --squash power-productivity
git commit -m "<squash message>"
git push "https://asamadiya:$(cat ~/my_stuff/pat)@github.com/asamadiya/dotfiles.git" master
```

---

## Self-review notes (author)

**Spec coverage cross-check:**

- §4 Shell stack → Tasks 9 (shared.sh), 10 (zshenv), 11 (zshrc + zinit), 12 (00–30 modules), 13 (aliases), 14 (modern-cli env), 15 (fzf), 16 (zoxide/atuin/direnv/carapace/starship inits), 17 (atuin config), 18 (starship config), 19 (tmux swap), 20 (cold-start gate).
- §5 Binary install → Tasks 1–7 (unified installer: scaffold + 5 batches + zsh special-case + nvim special-case).
- §6 Neovim → Tasks 8 (nvim install), 21 (NvChad), 22 (LazyVim).
- §7 File layout → Tasks 23 (install.sh wiring), 24 (sync.sh catch-up), every creating task above.
- §8 Acceptance → Post-implementation verification.
- §9 Rollback → Task 29 user guide's Rollback section.
- §13 Final deliverable → Task 29.

**Placeholder scan:** no `TBD`, `TODO`, or vague "similar to…" patterns in task bodies. Version pins labelled "example valid 2026-04-21 — verify at execution time" per spec §5.1.

**Scope check:** the spec bundles three sub-systems and user approved the bundle; 29 tasks decompose cleanly with no cross-task coupling that would force re-ordering.

**Type / name consistency:**
- `TOOL_VERSION[<name>]` array and `register <name> …` function used consistently from Task 1 through 6.
- `$BINDIR` env used consistently; defaults to `$HOME/.local/bin`.
- Aliases defined in Task 13's 40-aliases.zsh, extended in Task 22 for `lv` — no name conflicts.
- `shell/zshrc.d/*.zsh` naming convention (numeric prefix + `.zsh` suffix) used throughout Tasks 11–16.
