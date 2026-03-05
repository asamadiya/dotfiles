# Global CLAUDE.md 

## Environment
- Linux dev box with GPU (CUDA 11.8, TensorRT 8.6)
- Shell: bash, tmux (oh-my-tmux, prefix: C-space)
- Python 3 primary, PyTorch for ML workloads

## Shell Quirks
- `find` is aliased to `fd` — use Glob tool instead
- `grep` is aliased to `rg` — use Grep tool instead
- CUDA at /usr/local/cuda-11.8, TensorRT at /usr/local/TensorRT-8.6.1.6

## Workflow
- IMPORTANT: Be terse. No hand-holding. Lead with code.
- IMPORTANT: Write production code on first attempt. No TODOs or placeholders.
- Run tests/lints after changes to verify correctness before claiming done
- Commit atomically — one logical change per commit
- Use `claude --continue` to resume sessions, not fresh starts
- Use worktrees for parallel features: `claude --worktree <name>`
- Use agent teams for multi-perspective tasks (review, debugging, research)

## Git
- Branch naming: `feature-description` or `fix-description`
- Commit messages: imperative tense, concise, explain "why" not "what"
- Always run `git diff` before committing to verify changes

## Python Style
- Type hints on all public APIs
- f-strings over .format()
- dataclasses or attrs over raw dicts for structured data
- async where I/O bound, multiprocessing where CPU bound
