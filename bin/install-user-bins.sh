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
STATE_DIR="${STATE_DIR:-$HOME/.local/state/install-user-bins}"
mkdir -p "$BINDIR" "$STATE_DIR"

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
# install_tool <name> <version> <repo> <asset_tmpl> <bin_in_archive> [tag_tmpl]
#
# <asset_tmpl> and the optional <tag_tmpl> may reference {v} (version) and
# {V} ("v" prefix + version). If <tag_tmpl> is empty the default is "{V}"
# (tags of the form vX.Y.Z). Use "{v}" for repos whose tags are bare semver
# (e.g. ripgrep 15.1.0) or a literal string containing {v} for custom
# schemes (e.g. jq's "jq-{v}").
#
# <bin_in_archive> is the binary's path INSIDE the extracted tarball, or "-"
#                  if the downloaded file IS the binary (no archive).

install_tool() {
  local name="$1" version="$2" repo="$3" asset_tmpl="$4" bin_in_archive="$5"
  local tag_tmpl="${6:-{V\}}"

  # Idempotency via sentinel file: after each successful install, we write
  # the version string to $STATE_DIR/<name>.version. Parsing `<tool> --version`
  # is fragile (format drift, missing semver, non-standard prefixes) so we
  # trust the sentinel as the source of truth. Fallback: if the binary exists
  # but the sentinel does not (e.g. first run on a host that had the tool
  # installed by an older version of this script), re-install once so the
  # sentinel gets written.
  local sentinel="$STATE_DIR/$name.version"
  local installed_version=""
  if [[ -f "$sentinel" ]]; then
    installed_version=$(head -1 "$sentinel" 2>/dev/null || true)
  fi

  if (( ! FORCE )) && [[ -x "$BINDIR/$name" ]] && [[ "$installed_version" == "$version" ]]; then
    log "$name $version (already installed)"
    return 0
  fi

  local V="v$version" v="$version"
  local asset="${asset_tmpl//\{v\}/$v}"
  asset="${asset//\{V\}/$V}"
  local tag="${tag_tmpl//\{v\}/$v}"
  tag="${tag//\{V\}/$V}"
  bin_in_archive="${bin_in_archive//\{v\}/$v}"
  bin_in_archive="${bin_in_archive//\{V\}/$V}"
  local url="https://github.com/$repo/releases/download/$tag/$asset"

  log "fetching $name $version from $url"
  local work; work=$(mktemp -d)
  trap 'rm -rf "$work"' RETURN

  if ! curl -fsSL -o "$work/$asset" "$url"; then
    warn "$name: download failed ($url)"
    return 1
  fi

  local src=""
  case "$asset" in
    *.tar.gz|*.tgz)  tar xzf "$work/$asset" -C "$work"; src="$work/$bin_in_archive" ;;
    *.tar.bz2|*.tbz) tar xjf "$work/$asset" -C "$work"; src="$work/$bin_in_archive" ;;
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
  printf '%s\n' "$version" > "$sentinel"
  log "$name $version installed to $BINDIR/$name"
}

# --- TOOLS table -------------------------------------------------------------
# Keys are one-line arrays of (version repo asset_tmpl bin_in_archive).
# The implementer MUST resolve each version pin below against the tool's
# GitHub releases page AT IMPLEMENTATION TIME.

declare -A TOOL_VERSION=()
declare -A TOOL_REPO=()
declare -A TOOL_ASSET=()
declare -A TOOL_BIN=()
declare -A TOOL_TAG=()

register() {
  TOOL_VERSION[$1]=$2; TOOL_REPO[$1]=$3; TOOL_ASSET[$1]=$4; TOOL_BIN[$1]=$5
  TOOL_TAG[$1]="${6:-}"
}

# Smoke-test tool (this task only registers fzf; later tasks add the rest).
# Resolved 2026-04-19 against https://github.com/junegunn/fzf/releases/latest
register fzf 0.71.0 junegunn/fzf 'fzf-{v}-linux_amd64.tar.gz' 'fzf'

# Shell-critical tools — resolved 2026-04-19.
register atuin        18.15.2 atuinsh/atuin             'atuin-x86_64-unknown-linux-musl.tar.gz'          'atuin-x86_64-unknown-linux-musl/atuin'
register zoxide       0.9.9   ajeetdsouza/zoxide        'zoxide-{v}-x86_64-unknown-linux-musl.tar.gz'     'zoxide'
register starship     1.25.0  starship/starship         'starship-x86_64-unknown-linux-gnu.tar.gz'        'starship'
register direnv       2.37.1  direnv/direnv             'direnv.linux-amd64'                              '-'
register carapace     1.6.4   carapace-sh/carapace-bin  'carapace-bin_{v}_linux_amd64.tar.gz'             'carapace'

# Core CLI replacements — resolved 2026-04-19.
register bat          0.26.1  sharkdp/bat               'bat-{V}-x86_64-unknown-linux-gnu.tar.gz'         'bat-{V}-x86_64-unknown-linux-gnu/bat'
register eza          0.23.4  eza-community/eza         'eza_x86_64-unknown-linux-gnu.tar.gz'             'eza'
register fd           10.4.2  sharkdp/fd                'fd-{V}-x86_64-unknown-linux-gnu.tar.gz'          'fd-{V}-x86_64-unknown-linux-gnu/fd'
register rg           15.1.0  BurntSushi/ripgrep        'ripgrep-{v}-x86_64-unknown-linux-musl.tar.gz'    'ripgrep-{v}-x86_64-unknown-linux-musl/rg'              '{v}'
register delta        0.19.2  dandavison/delta          'delta-{v}-x86_64-unknown-linux-gnu.tar.gz'       'delta-{v}-x86_64-unknown-linux-gnu/delta'              '{v}'
register difft        0.68.0  Wilfred/difftastic        'difft-x86_64-unknown-linux-gnu.tar.gz'           'difft'                                                 '{v}'
register sd           1.1.0   chmln/sd                  'sd-{V}-x86_64-unknown-linux-gnu.tar.gz'          'sd-{V}-x86_64-unknown-linux-gnu/sd'
register jq           1.8.1   jqlang/jq                 'jq-linux-amd64'                                  '-'                                                     'jq-{v}'

# Git tooling — resolved 2026-04-19. See deviations in phase-log.
register lazygit          0.61.1   jesseduffield/lazygit      'lazygit_{v}_Linux_x86_64.tar.gz'                             'lazygit'
register gh-dash          4.23.2   dlvhdr/gh-dash             'gh-dash_{V}_linux-amd64'                                     '-'
register git-absorb       0.9.0    tummychow/git-absorb       'git-absorb-{v}-x86_64-unknown-linux-musl.tar.gz'             'git-absorb-{v}-x86_64-unknown-linux-musl/git-absorb' '{v}'
register git-branchless   0.10.0   arxanas/git-branchless     'git-branchless-{V}-x86_64-unknown-linux-musl.tar.gz'         'git-branchless'
register git-who          1.3      sinclairtarget/git-who     'gitwho_{V}_linux_amd64.tar.gz'                               'linux_amd64/git-who'
register spr              0.17.5   ejoffe/spr                 'spr_linux_x86_64.tar.gz'                                     'git-spr'
# onefetch: latest 2.27.1 built against GLIBC 2.39; this host is 2.38.
# Pin 2.21.0 which runs on 2.38 until host toolchain upgrades.
register onefetch         2.21.0   o2sh/onefetch              'onefetch-linux.tar.gz'                                       'onefetch'                                           '{v}'
register scc              3.7.0    boyter/scc                 'scc_Linux_x86_64.tar.gz'                                     'scc'

# Rest — resolved 2026-04-19.
register btop             1.4.6    aristocratos/btop          'btop-x86_64-unknown-linux-musl.tbz'                          'btop/bin/btop'
register hyperfine        1.20.0   sharkdp/hyperfine          'hyperfine-{V}-x86_64-unknown-linux-gnu.tar.gz'               'hyperfine-{V}-x86_64-unknown-linux-gnu/hyperfine'
register tldr             1.8.1    tealdeer-rs/tealdeer       'tealdeer-linux-x86_64-musl'                                  '-'
register just             1.50.0   casey/just                 'just-{v}-x86_64-unknown-linux-musl.tar.gz'                   'just'                                                  '{v}'
register watchexec        2.5.1    watchexec/watchexec        'watchexec-{v}-x86_64-unknown-linux-gnu.tar.xz'               'watchexec-{v}-x86_64-unknown-linux-gnu/watchexec'
register asciinema        3.2.0    asciinema/asciinema        'asciinema-x86_64-unknown-linux-musl'                         '-'
register vhs              0.11.0   charmbracelet/vhs          'vhs_{v}_Linux_x86_64.tar.gz'                                 'vhs_{v}_Linux_x86_64/vhs'
register yazi             26.1.22  sxyazi/yazi                'yazi-x86_64-unknown-linux-musl.zip'                          'yazi-x86_64-unknown-linux-musl/yazi'
register dust             1.2.4    bootandy/dust              'dust-{V}-x86_64-unknown-linux-gnu.tar.gz'                    'dust-{V}-x86_64-unknown-linux-gnu/dust'
register duf              0.9.1    muesli/duf                 'duf_{v}_linux_x86_64.tar.gz'                                 'duf'
register procs            0.14.11  dalance/procs              'procs-{V}-x86_64-linux.zip'                                  'procs'

# gh + yq — resolved 2026-04-19.
register gh               2.90.0   cli/cli                    'gh_{v}_linux_amd64.tar.gz'                                   'gh_{v}_linux_amd64/bin/gh'
register yq               4.53.2   mikefarah/yq               'yq_linux_amd64'                                              '-'

# Polyglot project env manager — resolved 2026-04-19.
# Pulled in ahead of the polyglot-env spec cycle (productivity §11 had deferred this).
# musl variant avoids host glibc 2.38 mismatches; tarball unpacks to a single `pixi` binary.
register pixi             0.67.1   prefix-dev/pixi            'pixi-x86_64-unknown-linux-musl.tar.gz'                       'pixi'

# --- special-case installers -------------------------------------------------

install_zsh() {
  # zsh-bin does not carry a script-side version pin — we just re-use whatever
  # the installer places. Use a synthetic "installed" marker in the sentinel so
  # repeated runs skip cleanly regardless of `zsh --version` drift.
  local target="$BINDIR/zsh"
  local sentinel="$STATE_DIR/zsh.version"
  if (( ! FORCE )) && [[ -x "$target" ]] && [[ -f "$sentinel" ]]; then
    log "zsh $(head -1 "$sentinel") (already installed)"
    return 0
  fi
  log "installing zsh via romkatv/zsh-bin"
  # zsh-bin's installer prompts interactively by default; `-e no -d ...` makes it scripted.
  if ! sh -c "$(curl -fsSL https://raw.githubusercontent.com/romkatv/zsh-bin/master/install)" \
       -- -e no -d "$HOME/.local"; then
    warn "zsh-bin installer failed"
    return 1
  fi
  local zsh_version
  zsh_version=$("$target" --version 2>/dev/null | awk '{print $2}' || true)
  printf '%s\n' "${zsh_version:-zsh-bin}" > "$sentinel"
  "$target" --version
}

install_nvim() {
  # Resolved 2026-04-19 against https://api.github.com/repos/neovim/neovim/releases
  # v0.12.1 runs on glibc 2.38 (verified).
  local version="0.12.1"
  local target="$BINDIR/nvim"
  local sentinel="$STATE_DIR/nvim.version"
  local installed_version=""
  if [[ -f "$sentinel" ]]; then
    installed_version=$(head -1 "$sentinel" 2>/dev/null || true)
  fi
  if (( ! FORCE )) && [[ -x "$target" ]] && [[ "$installed_version" == "$version" ]]; then
    log "nvim $version (already installed)"
    return 0
  fi
  log "installing nvim $version AppImage"
  local url="https://github.com/neovim/neovim/releases/download/v${version}/nvim-linux-x86_64.appimage"
  local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  if ! curl -fsSL -o "$tmp/nvim.appimage" "$url"; then
    warn "nvim download failed ($url)"
    return 1
  fi
  chmod +x "$tmp/nvim.appimage"
  # Try direct run (requires FUSE). Fall back to --appimage-extract if it fails.
  if "$tmp/nvim.appimage" --version >/dev/null 2>&1; then
    install -m755 "$tmp/nvim.appimage" "$target"
  else
    log "FUSE unavailable — extracting AppImage"
    (cd "$tmp" && ./nvim.appimage --appimage-extract >/dev/null)
    local payload="$HOME/.local/share/nvim-appimage"
    rm -rf "$payload"
    mkdir -p "$payload"
    cp -a "$tmp/squashfs-root/." "$payload/"
    ln -sfn "$payload/usr/bin/nvim" "$target"
  fi
  printf '%s\n' "$version" > "$sentinel"
  "$target" --version | head -1
}

# --- dispatch ----------------------------------------------------------------
tools=(zsh nvim "${!TOOL_VERSION[@]}")
if [[ -n "$SINGLE" ]]; then tools=("$SINGLE"); fi

failed=0
for t in "${tools[@]}"; do
  case "$t" in
    zsh)   install_zsh   || { failed=$((failed+1)); warn "zsh install FAILED"; }; continue ;;
    nvim)  install_nvim  || { failed=$((failed+1)); warn "nvim install FAILED"; }; continue ;;
  esac
  if [[ -z "${TOOL_VERSION[$t]:-}" ]]; then
    warn "unknown tool: $t"; failed=$((failed+1)); continue
  fi
  install_tool "$t" "${TOOL_VERSION[$t]}" "${TOOL_REPO[$t]}" "${TOOL_ASSET[$t]}" "${TOOL_BIN[$t]}" "${TOOL_TAG[$t]:-}" \
    || { failed=$((failed+1)); warn "$t install FAILED"; continue; }
  case "$t" in
    fzf)
      # fzf ships binary-only in releases. Fetch key-bindings.zsh + completion.zsh
      # from the repo at the pinned tag so 60-fzf.zsh can source them.
      fzf_v="${TOOL_VERSION[$t]}"
      fzf_dest="$HOME/.local/share/fzf"
      mkdir -p "$fzf_dest"
      if curl -fsSL "https://raw.githubusercontent.com/junegunn/fzf/v${fzf_v}/shell/key-bindings.zsh" \
           -o "$fzf_dest/key-bindings.zsh" \
         && curl -fsSL "https://raw.githubusercontent.com/junegunn/fzf/v${fzf_v}/shell/completion.zsh" \
           -o "$fzf_dest/completion.zsh"; then
        log "fzf shell integration installed at $fzf_dest"
      else
        warn "fzf shell integration fetch failed (non-fatal)"
      fi
      ;;
  esac
done

if (( failed )); then exit 1; fi
echo "install-user-bins: OK"
