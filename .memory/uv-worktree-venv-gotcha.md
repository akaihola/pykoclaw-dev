# uv sync + VIRTUAL_ENV in Worktrees

**Tags:** uv, worktree, gotcha, dev-workflow
**Related:** [worktree-workflow.md], [workspace-layout.md]

## Problem 1: `uv sync` wipes packages when VIRTUAL_ENV is wrong

When the parent shell has `VIRTUAL_ENV` set to the main workspace's
`.venv`, running `uv sync` in a worktree can uninstall packages from
the wrong venv.

**Fix:** Always `unset VIRTUAL_ENV` before running `uv sync` or
`uv run` in a worktree.

## Problem 2: New entry points not visible after deploy

When a package gains new `[project.entry-points]` (e.g. pykoclaw-messaging
adding `pykoclaw.plugins`), `install-dev.sh` (uv tool install) may not
rebuild that package. And `which pykoclaw` may resolve to the workspace
`.venv/bin/pykoclaw` (which has stale metadata) instead of
`~/.local/bin/pykoclaw` (the tool install).

**Fix:** After adding entry points:

1. Force rebuild: `uv tool install --force --reinstall-package <pkg> ...`
2. Sync workspace venv: `uv sync --all-packages`
3. Verify with `~/.local/bin/pykoclaw` directly, not just `pykoclaw`

**Discovered:** 2026-02-22 — `pykoclaw send --help` showed "No such
command" after deploy because the workspace `.venv` binary was on PATH
before `~/.local/bin`.

[worktree-workflow.md]: worktree-workflow.md
[workspace-layout.md]: workspace-layout.md
