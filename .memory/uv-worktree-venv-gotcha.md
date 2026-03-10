# uv sync + VIRTUAL_ENV in Worktrees

**Tags:** uv, worktree, gotcha, dev-workflow
**Related:** [worktree-workflow.md], [workspace-layout.md]

## Problem 1: `uv sync` wipes packages when VIRTUAL_ENV is wrong

When the parent shell has `VIRTUAL_ENV` set to the main workspace's
`.venv`, running `uv sync` in a worktree can uninstall packages from
the wrong venv.

**Fix:** Always `unset VIRTUAL_ENV` before running `uv sync` or
`uv run` in a worktree.

## Problem 2: Install mechanism changed (2026-02-24)

**Old:** `install-dev.sh` used `uv tool install -e` which put the binary
at `~/.local/bin/pykoclaw`. The workspace `.venv/bin/pykoclaw` had stale
metadata.

**New:** `install-dev.sh` now uses `uv pip install -e` into `~/.venv/`
(or `~/prg/pykoclaw-dev/.venv/`). The `uv tool` path (`~/.local/bin/pykoclaw`)
no longer exists. All configs (Mitto, systemd) must reference the `.venv`
binary.

**Wrapper scripts** (`~/.local/bin/pykoclaw-tyko`, `pykoclaw-ressu`) already
point to `~/prg/pykoclaw-dev/.venv/bin/pykoclaw` and are still correct.

[worktree-workflow.md]: worktree-workflow.md
[workspace-layout.md]: workspace-layout.md
