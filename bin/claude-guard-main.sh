#!/bin/bash
# PreToolUse hook: blocks file edits on main/master branch
# Exit code 2 blocks the operation and feeds stderr to Claude
branch=$(git branch --show-current 2>/dev/null)
if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    echo "BLOCKED: Cannot edit files on $branch branch. Create a feature branch first." >&2
    exit 2
fi
exit 0
