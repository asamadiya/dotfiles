#!/usr/bin/env bash
# state-snapshot.sh — rsync session state + shell history + logs into the state
# repo, age-encrypt sensitive buckets, commit locally. Never push.
#
# Work-side state repo path (default): ~/lin_code/state
# Override via env: STATE_REPO=/some/path state-snapshot.sh

set -eu

STATE_REPO="${STATE_REPO:-$HOME/lin_code/state}"
AGE_IDENTITY="$HOME/.config/age/state-identity.txt"

[ -d "$STATE_REPO/.git" ] || { echo "state repo not initialised at $STATE_REPO" >&2; exit 0; }
[ -f "$AGE_IDENTITY" ] || { echo "missing age identity at $AGE_IDENTITY" >&2; exit 0; }

# Extract the public key from the identity file. Identity format: one line
# starting with "# public key: age1..." above an "AGE-SECRET-KEY-..." private
# line. We encrypt with -r <pubkey> (non-interactive) and decrypt manually
# with age -d -i "$AGE_IDENTITY" <file>.age.
AGE_PUBKEY=$(awk '/^# public key:/{print $4; exit}' "$AGE_IDENTITY")
[ -n "$AGE_PUBKEY" ] || { echo "state-snapshot: could not extract public key from $AGE_IDENTITY" >&2; exit 0; }

HOST=$(hostname -s)

# --- rsync sources -----------------------------------------------------------
mkdir -p \
  "$STATE_REPO/claude/projects" \
  "$STATE_REPO/copilot/session-state" \
  "$STATE_REPO/atuin" \
  "$STATE_REPO/tmux/resurrect" \
  "$STATE_REPO/logs" \
  "$STATE_REPO/recordings" \
  "$STATE_REPO/snapshots/$HOST"

[ -d "$HOME/.claude/projects" ]        && rsync -a --delete "$HOME/.claude/projects/"       "$STATE_REPO/claude/projects/"
[ -d "$HOME/.copilot/session-state" ]  && rsync -a --delete "$HOME/.copilot/session-state/" "$STATE_REPO/copilot/session-state/"
[ -f "$HOME/.copilot/session-store.db" ] && cp -f "$HOME/.copilot/session-store.db" "$STATE_REPO/copilot/session-store.db"
[ -d "$HOME/.tmux/resurrect" ]         && rsync -a --delete --exclude='last' "$HOME/.tmux/resurrect/" "$STATE_REPO/tmux/resurrect/"

# --- age-encrypt atuin history (asymmetric — non-interactive) ---------------
if command -v age >/dev/null && [ -f "$HOME/.local/share/atuin/history.db" ]; then
  age -r "$AGE_PUBKEY" -o "$STATE_REPO/atuin/history.db.age" "$HOME/.local/share/atuin/history.db"
fi

# --- age-encrypt daily log rollup -------------------------------------------
TODAY=$(date +%Y-%m-%d)
LOG_DIR="$HOME/logs/tmux/$(date +%Y/%m/%d)"
if [ -d "$LOG_DIR" ]; then
  tar czf - -C "$LOG_DIR" . 2>/dev/null | age -r "$AGE_PUBKEY" -o "$STATE_REPO/logs/${TODAY}.tar.gz.age"
fi

# --- per-host inventory ------------------------------------------------------
{
  lscpu 2>/dev/null
  echo '---'
  lstopo --of txt 2>/dev/null
  echo '---'
  lsblk -f 2>/dev/null
  echo '---'
  lspci 2>/dev/null
  echo '---'
  cat /etc/os-release 2>/dev/null
  echo '---'
  uptime
  echo '---'
  df -h
} > "$STATE_REPO/snapshots/$HOST/inventory.txt" 2>/dev/null || true

# --- commit-time LFS + secret-pattern abort ---------------------------------
cd "$STATE_REPO"
git add -A

if command -v git-lfs >/dev/null; then
  touch .gitattributes
  staged=$(git diff --cached --name-only --diff-filter=ACMR)
  declare -A SEEN=()
  for f in $staged; do
    [ -f "$f" ] || continue
    if file --mime-encoding -- "$f" 2>/dev/null | grep -qE ': (binary|octet-stream)$'; then
      ext="${f##*.}"
      if [ -z "$ext" ] || [ "$ext" = "$f" ]; then continue; fi
      [ -n "${SEEN[$ext]:-}" ] && continue
      SEEN[$ext]=1
      pat="*.${ext}"
      grep -qxF "$pat filter=lfs diff=lfs merge=lfs -text" .gitattributes && continue
      git lfs track "$pat" >/dev/null
    fi
  done
  git add .gitattributes 2>/dev/null || true
  git add -u -- . 2>/dev/null || true
fi

PATTERNS='(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})'
for f in $(git diff --cached --name-only --diff-filter=ACMR); do
  [ -f "$f" ] || continue
  if git check-attr filter -- "$f" 2>/dev/null | grep -q 'filter: lfs'; then continue; fi
  if grep -Eq "$PATTERNS" "$f" 2>/dev/null; then
    echo "state-snapshot: aborting — secret pattern in $f" >&2
    systemd-cat -t state-snapshot -p err <<< "aborted: secret pattern in $f" 2>/dev/null || true
    git reset >/dev/null 2>&1 || true
    exit 2
  fi
done

# --- commit (skip if nothing to commit) --------------------------------------
if git diff --cached --quiet; then
  exit 0
fi
SUMMARY=$(git diff --cached --shortstat | sed 's/^ //')
git commit -m "snapshot $HOST $(date +%Y-%m-%dT%H:%MZ): ${SUMMARY:-update}" --no-verify >/dev/null
exit 0
