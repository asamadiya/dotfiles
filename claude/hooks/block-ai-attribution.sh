#!/usr/bin/env bash
# PreToolUse(Bash) guard: deny git/gh commands that carry AI attribution
# (Co-Authored-By Claude/Anthropic trailers, "Generated with Claude Code" footers).
set -eu

cmd=$(jq -r '.tool_input.command // ""')

printf '%s\n' "$cmd" | command grep -Eiq '(^|[^[:alnum:]_-])(git[[:space:]]+(commit|tag|notes|merge)|gh[[:space:]]+(pr|issue|api|release))([[:space:]]|$)' || exit 0
printf '%s\n' "$cmd" | command grep -Eiq 'co-authored-by:.*(claude|anthropic)|generated with \[?claude|claude\.(ai|com)/(code|claude-code)' || exit 0

jq -n '{hookSpecificOutput: {
  hookEventName: "PreToolUse",
  permissionDecision: "deny",
  permissionDecisionReason: "AI attribution (Co-Authored-By Claude, Generated with Claude Code) is not allowed in commits, PRs, or comments. Remove it and retry. See ~/.claude/rules/no-claude-attribution.md."
}}'
