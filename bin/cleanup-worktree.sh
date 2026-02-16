#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

REPOS=(
    "pykoclaw"
    "pykoclaw/pykoclaw"
    "pykoclaw-acp"
    "pykoclaw-chat"
    "pykoclaw-whatsapp"
    "pykoclaw-messaging"
)

print_status() { echo -e "${1}${2}${NC}"; }

[[ $# -lt 1 ]] && { print_status "$RED" "Error: Feature name required"; echo "Usage: $0 <feature-name>"; exit 1; }

FEATURE="$1"
WORKTREE_PATH="$HOME/pykoclaw-dev/$FEATURE"
TEMP_PYKOCLAW="/tmp/pykoclaw-dev-$FEATURE"
TEMP_MITTO="/tmp/mitto-dev-$FEATURE"

print_status "$YELLOW" "=== Cleaning up worktree for feature: $FEATURE ==="
echo ""

[[ ! -d "$WORKTREE_PATH" ]] && print_status "$YELLOW" "Worktree directory does not exist: $WORKTREE_PATH"

CLEANED_REPOS=()
FAILED_REPOS=()

for repo in "${REPOS[@]}"; do
    REPO_PATH="$HOME/$repo"
    WORKTREE_TO_REMOVE="$WORKTREE_PATH/$repo"

    if [[ -d "$REPO_PATH" ]] && git -C "$REPO_PATH" worktree list | grep -q "$WORKTREE_TO_REMOVE"; then
        print_status "$YELLOW" "Removing worktree: $WORKTREE_TO_REMOVE from $repo"

        if git -C "$REPO_PATH" worktree remove "$WORKTREE_TO_REMOVE" 2>/dev/null; then
            print_status "$GREEN" "  ✓ Removed worktree from $repo"
            CLEANED_REPOS+=("$repo")
        else
            print_status "$YELLOW" "  ! Force removing (possible uncommitted changes)"
            if git -C "$REPO_PATH" worktree remove --force "$WORKTREE_TO_REMOVE" 2>/dev/null; then
                print_status "$GREEN" "  ✓ Force removed worktree from $repo"
                CLEANED_REPOS+=("$repo")
            else
                print_status "$RED" "  ✗ Failed to remove worktree from $repo"
                FAILED_REPOS+=("$repo")
            fi
        fi
    else
        print_status "$YELLOW" "  - No worktree found for $repo"
    fi
done

echo ""
print_status "$YELLOW" "Running git worktree prune..."
git -C "$HOME/pykoclaw" worktree prune 2>/dev/null || true

echo ""
if [[ -d "$WORKTREE_PATH" ]]; then
    rm -rf "$WORKTREE_PATH"
    print_status "$GREEN" "✓ Removed $WORKTREE_PATH"
else
    print_status "$YELLOW" "Worktree directory not found: $WORKTREE_PATH"
fi

echo ""
for temp_dir in "$TEMP_PYKOCLAW" "$TEMP_MITTO"; do
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        print_status "$GREEN" "✓ Removed $temp_dir"
    else
        print_status "$YELLOW" "Temp data not found: $temp_dir"
    fi
done

echo ""
print_status "$GREEN" "=== Cleanup Summary ==="
echo ""

[[ ${#CLEANED_REPOS[@]} -gt 0 ]] && {
    print_status "$GREEN" "Worktrees removed from:"
    for repo in "${CLEANED_REPOS[@]}"; do echo "  ✓ $repo"; done
    echo ""
}

[[ ${#FAILED_REPOS[@]} -gt 0 ]] && {
    print_status "$RED" "Failed to remove worktrees from:"
    for repo in "${FAILED_REPOS[@]}"; do echo "  ✗ $repo"; done
    echo ""
}

print_status "$GREEN" "Cleanup complete for feature: $FEATURE"
