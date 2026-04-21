#!/usr/bin/env bash
# Lint every shell script in bin/ and tests/ using shellcheck.
# Exits non-zero if any script fails.

set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

while IFS= read -r f; do
  if ! shellcheck -x "$f"; then
    echo "shellcheck failed: $f" >&2
    failed=1
  fi
done < <(find "$ROOT/bin" "$ROOT/tests" -type f \( -name '*.sh' -o -name '*.bash' \) \
  -not -path '*/\.*' \
  2>/dev/null)

exit "$failed"
