#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Subrepos live in the *main* checkout, not in any worktree.
# Find the main worktree by locating the one on the 'main' branch.
MAIN_CHECKOUT="$(git -C "$WORKSPACE_ROOT" worktree list --porcelain \
    | awk '/^worktree/{path=$2} /^branch refs\/heads\/main/{print path; exit}')"
if [ -z "$MAIN_CHECKOUT" ]; then
    echo "Error: Could not determine main checkout path (no worktree on branch 'main')" >&2
    exit 1
fi

DEV_ROOT="$HOME/pykoclaw-dev"

AOE_BIN=""
if command -v aoe >/dev/null 2>&1; then
    AOE_BIN="$(command -v aoe)"
elif [ -x "$HOME/.cargo/bin/aoe" ]; then
    AOE_BIN="$HOME/.cargo/bin/aoe"
fi

SUBREPOS=(
    "pykoclaw"
    "pykoclaw-acp"
    "pykoclaw-chat"
    "pykoclaw-whatsapp"
    "pykoclaw-messaging"
)

if [ -z "${1:-}" ]; then
    echo "Error: Feature name required" >&2
    echo "Usage: $0 <feature-name>" >&2
    exit 1
fi

FEATURE_NAME="$1"

if ! [[ "$FEATURE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Feature name must contain only alphanumeric characters, dashes, and underscores" >&2
    exit 1
fi

BRANCH_NAME="feature/$FEATURE_NAME"
WORKTREE_BASE="$DEV_ROOT/$FEATURE_NAME"

echo "Creating worktrees for feature: $FEATURE_NAME"
echo "Branch: $BRANCH_NAME"
echo "Worktree root: $WORKTREE_BASE"
echo ""

if [ -e "$WORKTREE_BASE" ]; then
    echo "Error: Worktree base already exists: $WORKTREE_BASE" >&2
    exit 1
fi

# --- Workspace root repo (pykoclaw-dev) ---
# Its worktree IS the feature root — pyproject.toml and uv.lock come from git checkout.
echo "Processing: root (workspace)"
if git -C "$WORKSPACE_ROOT" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
    echo "  ERROR: Branch '$BRANCH_NAME' already exists in root" >&2
    exit 1
fi

echo "  Creating branch: $BRANCH_NAME"
git -C "$WORKSPACE_ROOT" branch "$BRANCH_NAME"

echo "  Creating worktree: $WORKTREE_BASE"
git -C "$WORKSPACE_ROOT" worktree add "$WORKTREE_BASE" "$BRANCH_NAME"
echo ""

# --- Subrepos ---
for repo in "${SUBREPOS[@]}"; do
    repo_path="$MAIN_CHECKOUT/$repo"
    worktree_path="$WORKTREE_BASE/$repo"

    echo "Processing: $repo"

    if git -C "$repo_path" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
        echo "  ERROR: Branch '$BRANCH_NAME' already exists in $repo" >&2
        echo "  Skipping..."
        echo ""
        continue
    fi

    if [ -d "$worktree_path" ]; then
        echo "  ERROR: Worktree already exists at $worktree_path" >&2
        echo "  Skipping..."
        echo ""
        continue
    fi

    echo "  Creating branch: $BRANCH_NAME"
    git -C "$repo_path" branch "$BRANCH_NAME" || {
        echo "  ERROR: Failed to create branch in $repo" >&2
        continue
    }

    echo "  Creating worktree: $worktree_path"
    git -C "$repo_path" worktree add "$worktree_path" "$BRANCH_NAME" || {
        echo "  ERROR: Failed to create worktree for $repo" >&2
        continue
    }

    echo ""
done

# --- uv sync ---
echo "Running uv sync in $WORKTREE_BASE..."
if (cd "$WORKTREE_BASE" && uv sync --all-packages) 2>&1; then
    echo "uv sync completed successfully."
else
    echo "WARNING: uv sync failed. Dependencies may need to be installed manually."
    echo "Run: cd $WORKTREE_BASE && uv sync --all-packages"
fi

# --- AoE sessions ---
if [ -n "$AOE_BIN" ]; then
    AOE_GROUP="pykoclaw/$FEATURE_NAME"
    echo ""
    echo "Configuring AoE sessions..."

    "$AOE_BIN" group create "$AOE_GROUP" >/dev/null 2>&1 || true

    # Root worktree is the feature base itself
    if "$AOE_BIN" add "$WORKTREE_BASE" --title "$FEATURE_NAME-root" --group "$AOE_GROUP" --cmd opencode >/dev/null 2>&1; then
        echo "  Added AoE session: $FEATURE_NAME-root"
    else
        echo "  WARNING: Failed to add AoE session: $FEATURE_NAME-root"
    fi

    for repo in "${SUBREPOS[@]}"; do
        worktree_path="$WORKTREE_BASE/$repo"
        session_title="$FEATURE_NAME-$repo"

        if [ ! -d "$worktree_path" ]; then
            continue
        fi

        if "$AOE_BIN" add "$worktree_path" --title "$session_title" --group "$AOE_GROUP" --cmd opencode >/dev/null 2>&1; then
            echo "  Added AoE session: $session_title"
        else
            echo "  WARNING: Failed to add AoE session: $session_title"
        fi
    done
else
    echo ""
    echo "AoE not found. Skipping AoE session creation."
fi

echo ""
echo "========================================"
echo "Worktrees created successfully!"
echo "========================================"
echo ""
echo "Feature: $FEATURE_NAME"
echo "Branch: $BRANCH_NAME"
echo "Worktree root: $WORKTREE_BASE"
echo ""
echo "Repos:"
echo "  - root: $WORKTREE_BASE"
for repo in "${SUBREPOS[@]}"; do
    echo "  - $repo: $WORKTREE_BASE/$repo"
done
echo ""
echo "To start working:"
echo "  cd $WORKTREE_BASE"
if [ -n "$AOE_BIN" ]; then
    echo "  aoe"
fi
