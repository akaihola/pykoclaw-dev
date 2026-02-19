#!/usr/bin/env bash
set -euo pipefail

# Merge feature branches back to main across all repos that have changes.

REPOS=(
    ""
    "pykoclaw"
    "pykoclaw-acp"
    "pykoclaw-chat"
    "pykoclaw-whatsapp"
    "pykoclaw-messaging"
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

for repo in "${REPOS[@]}"; do
    if [[ -z "$repo" ]]; then
        repo_path="$HOME/pykoclaw"
        repo_name="root"
    else
        repo_path="$HOME/pykoclaw/$repo"
        repo_name="$repo"
    fi

    if ! git -C "$repo_path" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        SKIPPED+=("$repo_name (no branch)")
        continue
    fi

    ahead=$(git -C "$repo_path" rev-list --count "main..$BRANCH" 2>/dev/null || echo 0)
    if [[ "$ahead" -eq 0 ]]; then
        SKIPPED+=("$repo_name (no changes)")
        continue
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
