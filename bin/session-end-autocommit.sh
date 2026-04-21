#!/usr/bin/env bash
# session-end-autocommit.sh <agent> <session-id>
#
# Called as a SessionEnd hook for Claude Code and from a trap EXIT wrapper for
# Copilot CLI. Commits the current working tree of the agent's cwd to the
# enclosing git repo. No push, no pre-commit, no Co-Authored-By.
#
# Behavior:
#   - Auto-adds binary files to Git LFS by extension (no `git lfs install` required).
#   - Aborts with a loud log if staged cleartext matches a known-secret regex.
#   - Exits 0 silently when: not in a repo / nothing to commit.

set -eu

AGENT="${1:-unknown}"
SID="${2:-unknown}"
SHORT="${SID:0:8}"

# --- locate repo root --------------------------------------------------------
if ! REPO=$(git rev-parse --show-toplevel 2>/dev/null); then
  exit 0  # not in a repo
fi

cd "$REPO"

# --- anything to commit? -----------------------------------------------------
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0  # clean
fi

# --- stage everything --------------------------------------------------------
git add -A

# --- LFS detection on staged binaries ---------------------------------------
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
else
  echo "session-end-autocommit: git-lfs not installed; skipping LFS detection" >&2
fi

# --- secret-pattern abort ---------------------------------------------------
PATTERNS='(ghp_|gho_|github_pat_|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})'
for f in $(git diff --cached --name-only --diff-filter=ACMR); do
  [ -f "$f" ] || continue
  # Skip files already LFS-tracked (binary blobs won't match regex anyway)
  if git check-attr filter -- "$f" 2>/dev/null | grep -q 'filter: lfs'; then continue; fi
  if grep -Eq "$PATTERNS" "$f" 2>/dev/null; then
    echo "session-end-autocommit: aborting — secret pattern in $f" >&2
    systemd-cat -t session-end-autocommit -p err <<< "aborted: secret pattern in $f" 2>/dev/null || true
    git reset >/dev/null 2>&1 || true
    exit 2
  fi
done

# --- commit ------------------------------------------------------------------
SUMMARY=$(git diff --cached --shortstat | sed 's/^ //')
MSG="session $AGENT $SHORT: ${SUMMARY:-working state snapshot}"
git commit -m "$MSG" --no-verify >/dev/null  # --no-verify only for THIS hook; manual commits still run pre-commit
exit 0
