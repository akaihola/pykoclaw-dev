#!/usr/bin/env bash
set -euo pipefail

# Merge feature branches back to main across all repos that have changes.
#
# Phase 1 — Adoption: before merging, scan the feature worktree for any new
# standalone git repos (i.e. dirs where .git is a DIRECTORY, not a file).
# These are plugins that were incorrectly created with `git init` directly in
# the worktree instead of via `bin/new-plugin.sh`.  Each one is adopted:
#   - cloned to its canonical location under MAIN_CHECKOUT
#   - the standalone dir is replaced with a proper worktree
#   - the workspace pyproject.toml in the feature branch is updated
#
# Phase 2 — Merge: auto-detect all subrepos (now including adopted ones) and
# merge feature/<name> → main for every repo that has commits ahead.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MAIN_CHECKOUT="$(git -C "$WORKSPACE_ROOT" worktree list --porcelain \
    | awk '/^worktree/{path=$2} /^branch refs\/heads\/main/{print path; exit}')"
if [[ -z "$MAIN_CHECKOUT" ]]; then
    echo "Error: Could not determine main checkout path (no worktree on branch 'main')" >&2
    exit 1
fi

if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <feature-name>" >&2
    echo "  Merges feature/<name> into main for repos with changes." >&2
    echo "  Automatically adopts any new plugins created in the feature worktree." >&2
    exit 1
fi

FEATURE="$1"
BRANCH="feature/$FEATURE"
WORKTREE_BASE="$HOME/prg/pykoclaw-worktrees/$FEATURE"

MERGED=()
SKIPPED=()
FAILED=()
ADOPTED=()

# ---------------------------------------------------------------------------
# Helper: add a package to the workspace members list in a pyproject.toml.
# Idempotent — does nothing if the member is already present.
# ---------------------------------------------------------------------------
_add_to_workspace() {
    local pyproject="$1"
    local member="$2"
    python3 -c "
import sys, re
path, m = sys.argv[1], sys.argv[2]
txt = open(path).read()
if '\"' + m + '\"' in txt:
    sys.exit(0)
txt = re.sub(
    r'(members\s*=\s*\[)(.*?)(\])',
    lambda x: x.group(1) + x.group(2) + ', \"' + m + '\"' + x.group(3),
    txt, flags=re.DOTALL)
open(path, 'w').write(txt)
" "$pyproject" "$member"
}

# ---------------------------------------------------------------------------
# Phase 1: adopt a new standalone repo from the feature worktree.
#
# A standalone repo has .git as a DIRECTORY (created via git init).
# A proper worktree has .git as a FILE (created via git worktree add).
#
# Adoption steps:
#   1. Clone to canonical location under MAIN_CHECKOUT (--local = hardlinks)
#   2. Rename branch to 'main' if needed (older git defaults to 'master')
#   3. Create feature branch pointing to the same commit
#   4. Check out main in the canonical repo
#   5. Delete the standalone dir and replace it with a proper worktree
#   6. Record the new member in the feature branch's pyproject.toml so that
#      the root-workspace merge (Phase 2) carries it to main automatically
# ---------------------------------------------------------------------------
_adopt_subrepo() {
    local name="$1"
    local src="$WORKTREE_BASE/$name"
    local dest="$MAIN_CHECKOUT/$name"

    echo "  Adopting '$name':"
    echo "    $src → $dest"

    git clone --local "$src" "$dest" 2>/dev/null
    git -C "$dest" remote remove origin

    # Normalize branch name to 'main'
    local cur_branch
    cur_branch="$(git -C "$dest" rev-parse --abbrev-ref HEAD)"
    if [[ "$cur_branch" != "main" ]]; then
        git -C "$dest" branch -m "$cur_branch" main
    fi

    # Ensure the feature branch exists (at the same commit as main)
    git -C "$dest" branch "$BRANCH" main 2>/dev/null || true
    git -C "$dest" checkout main >/dev/null 2>&1

    # Replace standalone repo with a proper worktree on the feature branch
    rm -rf "$src"
    git -C "$dest" worktree add "$src" "$BRANCH"

    # Update the feature branch's pyproject.toml so merge-feature carries it
    if [[ -f "$WORKTREE_BASE/pyproject.toml" ]]; then
        _add_to_workspace "$WORKTREE_BASE/pyproject.toml" "$name"
        if ! git -C "$WORKTREE_BASE" diff --quiet -- pyproject.toml 2>/dev/null; then
            git -C "$WORKTREE_BASE" add pyproject.toml
            git -C "$WORKTREE_BASE" commit \
                -m "chore: add $name to workspace members (adopted by merge-feature.sh)"
        fi
    fi

    ADOPTED+=("$name")
    echo "    ✓ adopted"
}

# ---------------------------------------------------------------------------
# Helper: merge a repo's feature branch into main
# ---------------------------------------------------------------------------
_merge_repo() {
    local repo_path="$1"
    local repo_name="$2"

    if ! git -C "$repo_path" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        SKIPPED+=("$repo_name (no branch)")
        return
    fi

    local ahead
    ahead=$(git -C "$repo_path" rev-list --count "main..$BRANCH" 2>/dev/null || echo 0)
    if [[ "$ahead" -eq 0 ]]; then
        SKIPPED+=("$repo_name (no changes)")
        return
    fi

    echo "  $repo_name: $ahead commit(s) ahead"
    if git -C "$repo_path" checkout main >/dev/null 2>&1 \
        && git -C "$repo_path" merge --no-ff --no-edit "$BRANCH" >/dev/null 2>&1; then
        MERGED+=("$repo_name")
    else
        git -C "$repo_path" merge --abort 2>/dev/null || true
        git -C "$repo_path" checkout main 2>/dev/null || true
        FAILED+=("$repo_name")
    fi
}

# ---------------------------------------------------------------------------
# Phase 1: adopt any new standalone repos from the feature worktree
# ---------------------------------------------------------------------------
if [[ -d "$WORKTREE_BASE" ]]; then
    for d in "$WORKTREE_BASE"/*/; do
        [[ -f "${d}pyproject.toml" ]] || continue
        [[ -d "${d}.git" ]] || continue   # .git as DIR = standalone repo (not a worktree)
        name="$(basename "$d")"
        [[ -d "$MAIN_CHECKOUT/$name" ]] && continue  # already in main checkout
        _adopt_subrepo "$name"
    done
fi

# ---------------------------------------------------------------------------
# Phase 2: detect subrepos and merge (auto-detects, includes newly adopted)
# ---------------------------------------------------------------------------
mapfile -t SUBREPOS < <(
    for d in "$MAIN_CHECKOUT"/*/; do
        [[ -f "${d}pyproject.toml" ]] && [[ -e "${d}.git" ]] && basename "$d"
    done
)

echo "Merging $BRANCH → main"
echo ""

_merge_repo "$WORKSPACE_ROOT" "root"

for repo in "${SUBREPOS[@]}"; do
    _merge_repo "$MAIN_CHECKOUT/$repo" "$repo"
done

echo ""
echo "========================================"
[[ ${#ADOPTED[@]} -gt 0 ]] && echo "Adopted: ${ADOPTED[*]}"
[[ ${#MERGED[@]}  -gt 0 ]] && echo "Merged:  ${MERGED[*]}"
[[ ${#SKIPPED[@]} -gt 0 ]] && echo "Skipped: ${SKIPPED[*]}"
[[ ${#FAILED[@]}  -gt 0 ]] && {
    echo "FAILED:  ${FAILED[*]}"
    echo ""
    echo "Resolve conflicts manually, then rerun or merge by hand."
    echo "========================================"
    exit 1
}
echo "========================================"

if [[ ${#MERGED[@]} -gt 0 || ${#ADOPTED[@]} -gt 0 ]]; then
    echo ""
    echo "Next steps:"
    echo "  ./install-dev.sh                    # deploy (editable reinstall)"
    echo "  bin/cleanup-worktree.sh $FEATURE    # tear down worktree"
fi
