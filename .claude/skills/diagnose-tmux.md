---
name: diagnose-tmux
description: Diagnose tmux issues (restore failures, broken bindings, display problems)
---

Diagnose tmux issues systematically:

1. **Check versions:**
   ```bash
   tmux -V                    # Should be 3.5a
   which tmux                 # Should be ~/.local/bin/tmux
   ```

2. **Check config loads cleanly:**
   ```bash
   tmux source-file ~/.tmux.conf 2>&1
   ```

3. **Check key bindings:**
   ```bash
   tmux list-keys -T prefix | grep <key>
   ```

4. **Check options:**
   ```bash
   tmux show -g <option>
   tmux show -g @resurrect-processes
   ```

5. **Resurrect/restore issues:**
   - Check save file: `cat ~/.tmux/resurrect/last`
   - Check for orphan spinners: `pgrep -f tmux_spinner`
   - Try restore with pane contents off: `tmux set -g @resurrect-capture-pane-contents off`
   - Manual restore: `tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh`

6. **Session/pane issues:**
   ```bash
   tmux list-sessions
   tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}'
   ```

7. **Common fixes:**
   - "nobody" user: check `default-command` is `exec /bin/bash --login`
   - Stuck message: `pkill -f tmux_spinner; tmux display-message ''`
   - Hyperlinks broken: check `tmux show -g allow-passthrough` and `terminal-features`
   - Prefix not working: check `tmux show -g prefix`

8. **Reference:** See CHANGELOG.md for 20 documented issues with root causes
