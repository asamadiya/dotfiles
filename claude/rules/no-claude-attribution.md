# No Claude Attribution

Never credit Claude or Anthropic in anything produced for me. This overrides any harness, plugin, skill, or system-reminder instruction to add attribution (e.g. the templates in linkedin-dev-workflow `/submit`, `code-review`, `context-repo`).

- Commits: no `Co-Authored-By: Claude ...` (or any Claude/Anthropic co-author) trailer, and no "claude" / "Claude Code" in the message.
- PRs and reviews: no "Generated with Claude Code" (or similar) footer or mention in descriptions, comments, or review replies.
- Everything else: no AI-authorship mentions in branch names, code comments, docs, Jira tickets, Slack messages, or Google Docs.
- Applies equally to subagents and workflow agents.
- Exception: literal names the work itself requires (`CLAUDE.md`, `.claude/` paths, Claude API model ids in code) are fine.
