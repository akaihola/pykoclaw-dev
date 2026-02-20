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
| **feature branch** | `feature/<name>` — created in every repo (root + subrepos)      |
| **worktree root**  | `~/pykoclaw-dev/<feature>/` — worktree of the pykoclaw-dev repo |
| **worktree**       | A git worktree checkout; subrepos live inside the worktree root |
| **AoE group**      | `pykoclaw/<feature>` — optional [AoE][aoe] session group        |

### Directory layout

```
~/pykoclaw-dev/<feature>/  ← worktree of the workspace root repo (pykoclaw-dev)
├── bin/                   ← scripts (checked out from branch)
├── pyproject.toml         ← real file (checked out from branch)
├── uv.lock                ← real file (checked out from branch)
├── pykoclaw/              ← worktree of pykoclaw (core)
├── pykoclaw-acp/          ← worktree of pykoclaw-acp
├── pykoclaw-chat/         ← worktree of pykoclaw-chat
├── pykoclaw-whatsapp/     ← worktree of pykoclaw-whatsapp
└── pykoclaw-messaging/    ← worktree of pykoclaw-messaging
```

The feature root **is** the workspace root worktree — `pyproject.toml` and
`uv.lock` are real checked-out files, so `uv sync --all-packages` works
immediately without any symlink setup.

## Scripts

All scripts live in `bin/` and take `<feature-name>` as the first argument.

### `bin/create-worktree.sh <feature>`

Creates a feature worktree. Steps:

1. Creates `feature/<feature>` branch in the workspace root repo
   (pykoclaw-dev) and adds its worktree at `~/pykoclaw-dev/<feature>/`
2. For each subrepo, creates `feature/<feature>` and adds its worktree
   at `~/pykoclaw-dev/<feature>/<subrepo>/`
3. Runs `uv sync --all-packages` in the worktree root
4. If [AoE][aoe] is available, creates an AoE session group
   `pykoclaw/<feature>` with one OpenCode session per repo

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

### `bin/staging.sh <feature>`

Launches Mitto web pointing at the worktree's pykoclaw ACP server for user
review. Opens a browser UI on an isolated port with isolated data:

- Generates a temp Mitto config at `/tmp/mitto-dev-<feature>/config.yaml`
- Sets `PYKOCLAW_DATA=/tmp/pykoclaw-dev-<feature>` (isolated from production)
- Uses `uv run --directory` so the worktree's code is what runs
- Unique port (hash-based, avoids 8080/8089)
- Ctrl+C stops everything

### `bin/merge-feature.sh <feature>`

Merges `feature/<feature>` into `main` for all repos that have commits ahead.
Skips repos with no branch or no changes. Reports merged/skipped/failed repos
and prints next steps (`install-dev.sh` + cleanup).

### `bin/run-dev.sh <feature>`

Prints commands for running an isolated dev environment manually (two-terminal
setup). Prefer `bin/staging.sh` for a single-command launch.

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

# 2. Work in the worktree — the feature root IS the workspace root
cd ~/pykoclaw-dev/my-feature
# ... edit code across repos ...

# 3. Run tests
bin/qa-check.sh my-feature

# 4. Launch staging for user review
bin/staging.sh my-feature
# → opens http://127.0.0.1:<port>, Ctrl+C to stop

# 5. Merge feature branches into main
bin/merge-feature.sh my-feature

# 6. Deploy (editable reinstall picks up merged code)
./install-dev.sh

# 7. Clean up worktree
bin/cleanup-worktree.sh my-feature

# 8. Optionally delete feature branches
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
