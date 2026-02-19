# Feature worktree workflow

The [pykoclaw-dev][pykoclaw-dev] workspace is checked out at `~/pykoclaw/`.
Each subdirectory (`pykoclaw/`, `pykoclaw-acp/`, etc.) is its own git repo. A
**feature worktree** creates parallel checkouts of *all* repos on a matching
feature branch so you can develop and test cross-repo changes without touching
`main`.

## Terminology

| Term               | Meaning                                                         |
| ------------------ | --------------------------------------------------------------- |
| **workspace**      | `~/pykoclaw/` — the [pykoclaw-dev][pykoclaw-dev] checkout       |
| **feature**        | A short alphanumeric name (e.g. `my-feature`)                   |
| **feature branch** | `feature/<name>` — created in every subrepo                     |
| **worktree root**  | `~/pykoclaw-dev/<feature>/` — top-level directory for worktrees |
| **worktree**       | A git worktree checkout for one repo inside the worktree root   |
| **AoE group**      | `pykoclaw/<feature>` — optional [AoE][aoe] session group        |

### Directory layout

```
~/pykoclaw-dev/<feature>/
├── root/                  ← worktree of the workspace root repo
├── pykoclaw/              ← worktree of pykoclaw (core)
├── pykoclaw-acp/          ← worktree of pykoclaw-acp
├── pykoclaw-chat/         ← worktree of pykoclaw-chat
├── pykoclaw-whatsapp/     ← worktree of pykoclaw-whatsapp
├── pykoclaw-messaging/    ← worktree of pykoclaw-messaging
├── pyproject.toml         ← symlink → workspace root's pyproject.toml
└── uv.lock                ← symlink → workspace root's uv.lock
```

Each subrepo worktree also gets symlinked `pyproject.toml` and `uv.lock` so
`uv sync --all-packages` works at the worktree root level.

## Scripts

All scripts live in `bin/` and take `<feature-name>` as the first argument.

### `bin/create-worktree.sh <feature>`

Creates a feature worktree. For each repo it:

1. Creates branch `feature/<feature>` from current HEAD
2. Creates a git worktree at `~/pykoclaw-dev/<feature>/<repo>`
3. Symlinks `pyproject.toml` and `uv.lock`
4. Runs `uv sync --all-packages` in the worktree root
5. If [AoE][aoe] is available, creates an AoE session group
   `pykoclaw/<feature>` with one OpenCode session per subrepo

### `bin/cleanup-worktree.sh <feature>`

Tears down a feature worktree. It:

1. Removes git worktrees from all repos (force-removes if dirty)
2. Removes AoE sessions and group (if AoE is available)
3. Runs `git worktree prune`
4. Deletes `~/pykoclaw-dev/<feature>/`
5. Deletes temp directories (`/tmp/pykoclaw-dev-<feature>`,
   `/tmp/mitto-dev-<feature>`)

**Note:** does NOT delete the `feature/<feature>` branches. Delete them
manually if no longer needed:

```bash
# In each subrepo:
git branch -d feature/<feature>
```

### `bin/list-worktrees.sh`

Lists active worktree directories under `~/pykoclaw-dev/` and AoE sessions
(if available).

### `bin/run-dev.sh <feature>`

Prints commands for running an isolated dev environment with:

- Unique port (hash-based, avoids 8080/8089)
- Temp data directory at `/tmp/pykoclaw-dev-<feature>`
- Temp Mitto config at `/tmp/mitto-dev-<feature>`
- AoE session info (if available)

### `bin/qa-check.sh [feature]`

Runs the full test suite against a feature worktree:

1. Preflight checks (uv, make, go, gcc, pytest)
2. `uv run pytest` in the worktree
3. `make test-go` and `make test-js` in Mitto

Auto-detects feature name from CWD if not provided.

## Typical workflow

```bash
# 1. Create feature worktree
bin/create-worktree.sh my-feature

# 2. Work in the worktree
cd ~/pykoclaw-dev/my-feature/root
# ... edit code across repos ...

# 3. Run tests
bin/qa-check.sh my-feature

# 4. When done, clean up
bin/cleanup-worktree.sh my-feature

# 5. Optionally delete feature branches
for repo in pykoclaw pykoclaw-acp pykoclaw-chat pykoclaw-whatsapp pykoclaw-messaging; do
    git -C ~/pykoclaw/$repo branch -d feature/my-feature 2>/dev/null
done
git branch -d feature/my-feature 2>/dev/null
```

## AoE integration

If [AoE][aoe] (Agent of Empires) is installed, the scripts automatically manage
OpenCode agent sessions grouped by feature. This is optional — scripts degrade
gracefully when AoE is not available.

[aoe]: https://github.com/njbrake/agent-of-empires
[pykoclaw-dev]: https://github.com/akaihola/pykoclaw-dev
