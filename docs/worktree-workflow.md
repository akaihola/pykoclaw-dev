# Feature worktree workflow

The [pykoclaw-dev][pykoclaw-dev] workspace is checked out at `~/pykoclaw/`.
Each subdirectory (`pykoclaw/`, `pykoclaw-acp/`, etc.) is its own git repo. A
**feature worktree** creates parallel checkouts of _all_ repos on a matching
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

## How subrepos are discovered

Scripts **do not maintain a hardcoded list** of subrepos. Instead, each script
scans `~/pykoclaw/*/` (or `--root` for `diff-repos.sh`) and selects every
subdirectory that has both a `pyproject.toml` and a `.git` entry. Adding a new
package to `~/pykoclaw/` makes it automatically visible to all scripts — no
script edits required.

## Scripts

All scripts live in `bin/` and take `<feature-name>` as the first argument.

### `bin/create-worktree.sh <feature>`

Creates a feature worktree. Steps:

1. Creates `feature/<feature>` branch in the workspace root repo
   (pykoclaw-dev) and adds its worktree at `~/pykoclaw-dev/<feature>/`
2. Auto-detects all subrepos and for each creates `feature/<feature>` + worktree
   at `~/pykoclaw-dev/<feature>/<subrepo>/`
3. Runs `uv sync --all-packages` in the worktree root
4. If [AoE][aoe] is available, creates an AoE session group
   `pykoclaw/<feature>` with one OpenCode session per repo

### `bin/new-plugin.sh <feature> <plugin-name>`

Creates a new plugin subrepo **correctly** inside an existing feature worktree.
This is the only supported way to add a new package during feature development.
Never `git init` directly in the feature worktree — see [adding a new plugin].

Steps:

1. Initialises canonical git repo at `~/pykoclaw/<plugin-name>/` with an
   initial scaffold commit on `main`
2. Creates `feature/<feature>` branch in the canonical repo
3. Adds a git worktree at `~/pykoclaw-dev/<feature>/<plugin-name>/`
4. Records the new package in the workspace `pyproject.toml` on the feature
   branch and commits it (merge-feature.sh carries this to main)
5. Runs `uv sync --all-packages`
6. Creates an AoE session if available

### `bin/merge-feature.sh <feature>`

Merges `feature/<feature>` into `main` for all repos with commits ahead.
Runs in two phases:

**Phase 1 — Adoption:** scans the feature worktree for any standalone git repos
(dirs where `.git` is a directory, not a file — i.e. created via `git init`
rather than `git worktree add`). For each one not already in `~/pykoclaw/`:

- Clones it to `~/pykoclaw/<name>/` (the canonical location)
- Replaces the standalone dir with a proper git worktree
- Commits the new workspace member to the feature branch's `pyproject.toml`

**Phase 2 — Merge:** auto-detects all subrepos (now including newly adopted
ones) and merges `feature/<feature>` → `main` for each with commits ahead.

### `bin/cleanup-worktree.sh <feature>`

Tears down a feature worktree. Before removing anything it checks for
**unadopted standalone repos** — new plugins that exist only in the feature
worktree (`.git` is a directory) and haven't been merged yet. If any are found
it prints a warning and refuses to proceed in non-interactive mode; in a
terminal it prompts for confirmation. Always run `merge-feature.sh` first.

Cleanup steps:

1. Preflight: detect unadopted repos and warn / abort
2. Removes git worktrees from all repos (force-removes if dirty)
3. Removes AoE sessions and group (if AoE is available)
4. Runs `git worktree prune`
5. Deletes `~/pykoclaw-dev/<feature>/`
6. Deletes temp directories (`/tmp/pykoclaw-dev-<feature>`,
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

### `bin/diff-feature.sh <feature>`

Thin wrapper around `diff-repos.sh` for the common feature-worktree case.
Equivalent to:

```bash
bin/diff-repos.sh --root=~/pykoclaw-dev/<feature> main
```

### `bin/diff-repos.sh [OPTIONS] [REF]`

General-purpose interactive multi-repo diff browser powered by **fzf + delta**.
Lists every changed file across all repos in a scrollable pane; the right pane
renders a live syntax-highlighted diff via `delta`.

| Option / Argument | Meaning                                                  |
| ----------------- | -------------------------------------------------------- |
| `--root=DIR`      | Workspace root to scan (default: `~/pykoclaw`)           |
| `--before=TIME`   | Diff vs last commit before TIME in each repo (see below) |
| `REF`             | Any git ref: branch, tag, SHA, `HEAD~N` …                |
| _(no args)_       | Uncommitted changes (`git diff HEAD`) in `~/pykoclaw`    |

`--before=TIME` accepts any format git understands: `"2025-01-15 14:00"`,
`"yesterday"`, `"2 hours ago"`. Each repo independently resolves its own SHA
for that point in time, so cross-repo snapshots are always consistent.

Keys inside the browser:

| Key               | Action                                      |
| ----------------- | ------------------------------------------- |
| ↑ / ↓             | Navigate the file list                      |
| Shift-↑ / Shift-↓ | Scroll preview one line up / down           |
| Ctrl-U / Ctrl-D   | Scroll preview half a page up / down        |
| Alt-V / Ctrl-V    | Scroll preview full page up / down          |
| PgUp / PgDn       | Scroll preview full page up / down          |
| Enter             | Open the selected file's full diff in delta |
| Ctrl-A            | Open the whole-repo diff for that entry     |
| Ctrl-C / q        | Quit                                        |

Examples:

```bash
bin/diff-repos.sh                              # uncommitted changes in ~/pykoclaw
bin/diff-repos.sh HEAD~5                       # vs 5 commits ago in each repo
bin/diff-repos.sh main                         # vs main branch in ~/pykoclaw
bin/diff-repos.sh --before="2025-01-15 14:00" # vs last commit before that time
bin/diff-repos.sh --root=~/pykoclaw-dev/feat main  # same as diff-feature.sh feat
```

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

# 2. Work in the worktree
cd ~/pykoclaw-dev/my-feature
# ... edit code across repos ...

# 3. Run tests
bin/qa-check.sh my-feature

# 4. Launch staging for user review
bin/staging.sh my-feature
# → opens http://127.0.0.1:<port>, Ctrl+C to stop

# 5. Review all cross-repo changes before merging
bin/diff-feature.sh my-feature

# 6. Merge feature branches into main (also adopts any new plugins)
bin/merge-feature.sh my-feature

# 7. Deploy (editable reinstall picks up merged code)
./install-dev.sh

# 8. Clean up worktree
bin/cleanup-worktree.sh my-feature

# 9. Optionally delete feature branches
for d in ~/pykoclaw/*/; do
    [[ -f "${d}pyproject.toml" ]] && [[ -e "${d}.git" ]] || continue
    git -C "$d" branch -d feature/my-feature 2>/dev/null || true
done
git branch -d feature/my-feature 2>/dev/null
```

## Adding a new plugin

Use `bin/new-plugin.sh` to create a new package inside an existing feature
worktree. This sets up both the canonical repo (in `~/pykoclaw/`) and the
worktree correctly from the start.

```bash
# Inside an existing feature worktree session:
bin/new-plugin.sh my-feature pykoclaw-myplugin

# Develop the new plugin
cd ~/pykoclaw-dev/my-feature/pykoclaw-myplugin/
# ... write code, add tests, commit ...

# Merge as usual — the new plugin is included automatically
bin/merge-feature.sh my-feature
./install-dev.sh
bin/cleanup-worktree.sh my-feature
```

### What happens if you `git init` in the worktree instead

If a new plugin was accidentally created at
`~/pykoclaw-dev/<feature>/<name>/` with `git init` (`.git` is a directory),
`merge-feature.sh` will detect it in Phase 1 and adopt it automatically:

1. Clones the repo to `~/pykoclaw/<name>/` (canonical location)
2. Renames the branch to `main` if needed
3. Replaces the standalone dir with a proper git worktree on `feature/<feature>`
4. Commits the new workspace member to the feature branch's `pyproject.toml`
5. Phase 2 merges proceed normally

So the workflow is still:

```bash
bin/merge-feature.sh my-feature   # adoption happens automatically in Phase 1
./install-dev.sh
bin/cleanup-worktree.sh my-feature
```

[adding a new plugin]: #adding-a-new-plugin

## AoE integration

If [AoE][aoe] (Agent of Empires) is installed, the scripts automatically manage
OpenCode agent sessions grouped by feature. This is optional — scripts degrade
gracefully when AoE is not available.

[aoe]: https://github.com/njbrake/agent-of-empires
[pykoclaw-dev]: https://github.com/akaihola/pykoclaw-dev
