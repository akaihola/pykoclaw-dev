#!/usr/bin/env bash
set -euo pipefail

# Merge feature branches back to main across all repos that have changes.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Subrepos live in the main checkout — find it via git worktree list.
MAIN_CHECKOUT="$(git -C "$WORKSPACE_ROOT" worktree list --porcelain \
    | awk '/^worktree/{path=$2} /^branch refs\/heads\/main/{print path; exit}')"
if [ -z "$MAIN_CHECKOUT" ]; then
    echo "Error: Could not determine main checkout path (no worktree on branch 'main')" >&2
    exit 1
fi

SUBREPOS=(
    "pykoclaw"
    "pykoclaw-acp"
    "pykoclaw-chat"
    "pykoclaw-whatsapp"
    "pykoclaw-messaging"
    "pykoclaw-matrix"
    "pykoclaw-slack"
    "pykoclaw-vision"
)

if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <feature-name>" >&2
    echo "  Merges feature/<name> into main for repos with changes" >&2
    exit 1
fi

FEATURE="$1"
BRANCH="feature/$FEATURE"

echo "Merging $BRANCH → main"
echo ""

MERGED=()
SKIPPED=()
FAILED=()

merge_repo() {
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
        && git -C "$repo_path" merge --no-edit "$BRANCH" >/dev/null 2>&1; then
        MERGED+=("$repo_name")
    else
        git -C "$repo_path" merge --abort 2>/dev/null || true
        git -C "$repo_path" checkout main 2>/dev/null || true
        FAILED+=("$repo_name")
    fi
}

# --- Workspace root repo ---
merge_repo "$WORKSPACE_ROOT" "root"

# --- Subrepos ---
for repo in "${SUBREPOS[@]}"; do
    merge_repo "$MAIN_CHECKOUT/$repo" "$repo"
done

echo ""
echo "========================================"
[[ ${#MERGED[@]} -gt 0 ]] && {
    echo "Merged:  ${MERGED[*]}"
}
[[ ${#SKIPPED[@]} -gt 0 ]] && {
    echo "Skipped: ${SKIPPED[*]}"
}
[[ ${#FAILED[@]} -gt 0 ]] && {
    echo "FAILED:  ${FAILED[*]}"
    echo ""
    echo "Resolve conflicts manually, then rerun or merge by hand."
    echo "========================================"
    exit 1
}
echo "========================================"

if [[ ${#MERGED[@]} -gt 0 ]]; then
    echo ""
    echo "Next steps:"
    echo "  ./install-dev.sh          # deploy (editable reinstall)"
    echo "  bin/cleanup-worktree.sh $FEATURE   # tear down worktree"
fi
