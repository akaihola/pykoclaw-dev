#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
WORKSPACE_ROOT="$SCRIPT_DIR/.."
DEV_ROOT="$HOME/pykoclaw-dev"

REPOS=(
    ""
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

mkdir -p "$WORKTREE_BASE"

for repo in "${REPOS[@]}"; do
    if [ -z "$repo" ]; then
        repo_path="$WORKSPACE_ROOT"
        repo_name="root"
    else
        repo_path="$WORKSPACE_ROOT/$repo"
        repo_name="$repo"
    fi
    
    worktree_path="$WORKTREE_BASE/$repo_name"
    
    echo "Processing: $repo_name"
    
    if git -C "$repo_path" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
        echo "  ERROR: Branch '$BRANCH_NAME' already exists in $repo_name" >&2
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
        echo "  ERROR: Failed to create branch in $repo_name" >&2
        continue
    }
    
    echo "  Creating worktree: $worktree_path"
    git -C "$repo_path" worktree add "$worktree_path" "$BRANCH_NAME" || {
        echo "  ERROR: Failed to create worktree for $repo_name" >&2
        continue
    }
    
    if [ -n "$repo" ]; then
        if [ -f "$repo_path/pyproject.toml" ]; then
            ln -sf "$repo_path/pyproject.toml" "$worktree_path/pyproject.toml"
            echo "  Linked pyproject.toml"
        fi
        if [ -f "$repo_path/uv.lock" ]; then
            ln -sf "$repo_path/uv.lock" "$worktree_path/uv.lock"
            echo "  Linked uv.lock"
        fi
    fi
    
    echo ""
done

echo "Running uv sync in $WORKTREE_BASE..."
if uv sync --workdir "$WORKTREE_BASE" 2>&1; then
    echo "uv sync completed successfully."
else
    echo "WARNING: uv sync failed. Dependencies may need to be installed manually."
    echo "Run: cd $WORKTREE_BASE && uv sync"
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
for repo in "${REPOS[@]}"; do
    if [ -z "$repo" ]; then
        echo "  - root: $WORKTREE_BASE/root"
    else
        echo "  - $repo: $WORKTREE_BASE/$repo"
    fi
done
echo ""
echo "To start working:"
echo "  cd $WORKTREE_BASE"
