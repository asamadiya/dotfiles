---
name: diagnose-claude-restore
description: Debug Claude Code session restoration in tmux
---

Debug Claude Code session restoration:

1. **Check if restore script exists and is executable:**
   ```bash
   ls -la ~/bin/tmux-claude-restore
   ```

2. **Check resurrect process config:**
   ```bash
   tmux show -g @resurrect-processes
   # Should contain: claude->/home/.../bin/tmux-claude-restore
   ```

3. **Check saved session map:**
   ```bash
   cat ~/.tmux/resurrect/claude_sessions
   ```

4. **Check for leaked env vars in pane:**
   ```bash
   tmux send-keys -t <pane> 'env | grep -i claude' C-m
   ```
   If `CLAUDE_CODE_SESSION`, `CLAUDE_CODE_ENTRY_POINT`, or `CLAUDECODE` are set, unset them:
   ```bash
   tmux send-keys -t <pane> 'unset CLAUDE_CODE_SESSION CLAUDE_CODE_ENTRY_POINT CLAUDECODE' C-m
   ```

5. **Manual restore to a specific pane:**
   ```bash
   tmux send-keys -t <session>:<window>.<pane> 'cd /path/to/project && claude --continue' C-m
   ```

6. **Check claude project directory mapping:**
   ```bash
   # Claude stores sessions at ~/.claude/projects/<path-with-dashes>/
   ls ~/.claude/projects/
   # e.g., $HOME/myproject -> -home-user-myproject
   ```

7. **Root causes for restore failure:**
   - Pane contents restore crashed sessions (fix: disable pane contents)
   - Env vars leaked from original session (fix: unset all 3 vars)
   - Session map empty (fix: run save hook manually first)
   - Process matching failed (fix: check `ps` output matches `claude` exactly)
