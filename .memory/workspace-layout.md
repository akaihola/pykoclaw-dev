# Workspace Layout

**Tags:** workspace, git, uv
**Related:** [plugin-system.md]

This is a **uv workspace** with 5 members declared in the root `pyproject.toml`.
Each subdirectory is also its own **git repository**.

Key implications:
- `git commit` in the workspace root only affects workspace-level files
  (`pyproject.toml`, `README.md`, `CLAUDE.md`, `.memory/`, scripts).
- Changes inside `pykoclaw/`, `pykoclaw-chat/`, etc. must be committed in those
  subdirectories' own repos.
- `./pull-all.sh` runs `git pull --rebase` in every subdir.
- `./install-dev.sh` installs all packages in editable mode via `uv tool install -e`.
- The root `pyproject.toml` has **no dependencies** — it only declares workspace
  membership.

[plugin-system.md]: plugin-system.md
