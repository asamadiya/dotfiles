---
name: add-dotfile
description: Add a new dotfile to be tracked by the repo
---

Add a new dotfile to the dotfiles repo:

1. Determine the live path (e.g., `~/.vimrc`) and repo path (e.g., `vim/vimrc`)
2. Copy the live file into the repo at the appropriate location
3. Add the mapping to `sync.sh` in the `FILES` associative array:
   ```
   ["$HOME/.vimrc"]="$DOTFILES/vim/vimrc"
   ```
4. Add a symlink entry in `install.sh`:
   ```
   link "$DOTFILES/vim/vimrc" "$HOME/.vimrc"
   ```
5. If the file needs special handling (like systemd template generation), document it
6. Update README.md repo structure section
7. Run `./sync.sh` to verify no diff
8. Commit with message: "Track <filename> in dotfiles"
