#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Subrepos live in the main checkout — find it via git worktree list.
MAIN_CHECKOUT="$(git -C "$WORKSPACE_ROOT" worktree list --porcelain \
    | awk '/^worktree/{path=$2} /^branch refs\/heads\/main/{print path; exit}')"
if [ -z "$MAIN_CHECKOUT" ]; then
    echo "Error: Could not determine main checkout path (no worktree on branch 'main')" >&2
    exit 1
fi

# Auto-detect subrepos: every subdirectory of MAIN_CHECKOUT that has both a
# pyproject.toml and a .git entry.  No manual list needed.
mapfile -t SUBREPOS < <(
    for d in "$MAIN_CHECKOUT"/*/; do
        [[ -f "${d}pyproject.toml" ]] && [[ -e "${d}.git" ]] && basename "$d"
    done
)

AOE_BIN=""
if command -v aoe >/dev/null 2>&1; then
    AOE_BIN="$(command -v aoe)"
elif [ -x "$HOME/.cargo/bin/aoe" ]; then
    AOE_BIN="$HOME/.cargo/bin/aoe"
fi

print_status() { echo -e "${1}${2}${NC}"; }

[[ $# -lt 1 ]] && { print_status "$RED" "Error: Feature name required"; echo "Usage: $0 <feature-name>"; exit 1; }

FEATURE="$1"
WORKTREE_BASE="$HOME/pykoclaw-dev/$FEATURE"
TEMP_PYKOCLAW="/tmp/pykoclaw-dev-$FEATURE"
TEMP_MITTO="/tmp/mitto-dev-$FEATURE"

print_status "$YELLOW" "=== Cleaning up worktree for feature: $FEATURE ==="
echo ""

[[ ! -d "$WORKTREE_BASE" ]] && print_status "$YELLOW" "Worktree directory does not exist: $WORKTREE_BASE"

CLEANED_REPOS=()
FAILED_REPOS=()

# --- Safety check: warn about new standalone repos not yet adopted ---
# A standalone repo has .git as a DIRECTORY; a proper worktree has .git as a FILE.
# If any exist in the worktree but not in MAIN_CHECKOUT, their commits will be
# permanently lost when WORKTREE_BASE is deleted.
UNADOPTED=()
if [[ -d "$WORKTREE_BASE" ]]; then
    for d in "$WORKTREE_BASE"/*/; do
        [[ -f "${d}pyproject.toml" ]] || continue
        [[ -d "${d}.git" ]] || continue   # .git as DIR = standalone repo
        name="$(basename "$d")"
        [[ -d "$MAIN_CHECKOUT/$name" ]] && continue
        UNADOPTED+=("$name")
        print_status "$RED" "WARNING: '$name' is a new repo not yet adopted into $MAIN_CHECKOUT"
        print_status "$RED" "         Its commits will be permanently deleted by cleanup."
    done
fi
if [[ ${#UNADOPTED[@]} -gt 0 ]]; then
    echo ""
    print_status "$YELLOW" "Run 'bin/merge-feature.sh $FEATURE' first to adopt and preserve these repos."
    echo ""
    if [[ -t 0 ]]; then
        read -r -p "Proceed with cleanup anyway and permanently lose the above? [y/N] " _confirm
        if [[ "${_confirm,,}" != "y" ]]; then
            print_status "$YELLOW" "Cleanup aborted."
            exit 1
        fi
    else
        print_status "$RED" "Running non-interactively — aborting to prevent data loss."
        exit 1
    fi
fi

# --- Subrepos ---
for repo in "${SUBREPOS[@]}"; do
    repo_path="$MAIN_CHECKOUT/$repo"
    worktree_to_remove="$WORKTREE_BASE/$repo"

    if [[ -d "$repo_path" ]] && git -C "$repo_path" worktree list | grep -q "$worktree_to_remove"; then
        print_status "$YELLOW" "Removing worktree: $worktree_to_remove from $repo"

        if git -C "$repo_path" worktree remove "$worktree_to_remove" 2>/dev/null; then
            print_status "$GREEN" "  ✓ Removed worktree from $repo"
            CLEANED_REPOS+=("$repo")
        else
            print_status "$YELLOW" "  ! Force removing (possible uncommitted changes)"
            if git -C "$repo_path" worktree remove --force "$worktree_to_remove" 2>/dev/null; then
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

# --- Workspace root (pykoclaw-dev) — worktree IS the feature base ---
if git -C "$WORKSPACE_ROOT" worktree list | grep -q "$WORKTREE_BASE"; then
    print_status "$YELLOW" "Removing worktree: $WORKTREE_BASE from root"

    if git -C "$WORKSPACE_ROOT" worktree remove "$WORKTREE_BASE" 2>/dev/null; then
        print_status "$GREEN" "  ✓ Removed worktree from root"
        CLEANED_REPOS+=("root")
    else
        print_status "$YELLOW" "  ! Force removing (possible uncommitted changes)"
        if git -C "$WORKSPACE_ROOT" worktree remove --force "$WORKTREE_BASE" 2>/dev/null; then
            print_status "$GREEN" "  ✓ Force removed worktree from root"
            CLEANED_REPOS+=("root")
        else
            print_status "$RED" "  ✗ Failed to remove worktree from root"
            FAILED_REPOS+=("root")
        fi
    fi
else
    print_status "$YELLOW" "  - No worktree found for root"
fi

# --- AoE sessions ---
if [[ -n "$AOE_BIN" ]]; then
    AOE_GROUP="pykoclaw/$FEATURE"

    print_status "$YELLOW" ""
    print_status "$YELLOW" "Removing AoE sessions for group: $AOE_GROUP"

    for repo_name in "root" "${SUBREPOS[@]}"; do
        session_title="$FEATURE-$repo_name"
        if "$AOE_BIN" remove "$session_title" >/dev/null 2>&1; then
            print_status "$GREEN" "  ✓ Removed AoE session: $session_title"
        else
            print_status "$YELLOW" "  - AoE session not found: $session_title"
        fi
    done

    "$AOE_BIN" group delete "$AOE_GROUP" --force >/dev/null 2>&1 || true
fi

echo ""
print_status "$YELLOW" "Running git worktree prune..."
git -C "$WORKSPACE_ROOT" worktree prune 2>/dev/null || true
for repo in "${SUBREPOS[@]}"; do
    git -C "$MAIN_CHECKOUT/$repo" worktree prune 2>/dev/null || true
done

echo ""
if [[ -d "$WORKTREE_BASE" ]]; then
    rm -rf "$WORKTREE_BASE"
    print_status "$GREEN" "✓ Removed $WORKTREE_BASE"
else
    print_status "$YELLOW" "Worktree directory not found: $WORKTREE_BASE"
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
