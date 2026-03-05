---
name: sync-dotfiles
description: Sync dotfiles between live system and repo
---

Sync dotfiles using the bidirectional sync script:

**Pull (live -> repo):**
```bash
cd ~/dotfiles
./sync.sh              # Show diff only
./sync.sh --commit     # Pull + auto-commit
```

**Push (repo -> live):**
```bash
cd ~/dotfiles
./sync.sh --push       # Copies repo files to live system (backs up existing)
```

**After pushing, reload affected configs:**
```bash
source ~/.bash_profile                    # Shell
tmux source-file ~/.tmux.conf            # Tmux
systemctl --user daemon-reload            # Systemd
```

**Adding new files to track:**
Use the `add-dotfile` skill.

**Mapping is in `sync.sh`:**
- `FILES` associative array: config file mappings
- `BIN_SCRIPTS` array: scripts in ~/bin
- Claude agents: auto-synced from `~/.claude/agents/*.md`
