#!/usr/bin/env bash
# diff-feature.sh <feature-name>
#
# Thin wrapper around diff-repos.sh for feature worktree diffs.
# Shows all files changed vs main across every repo in the worktree.
# For more options (uncommitted changes, before-timestamp), use diff-repos.sh directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <feature-name>" >&2
    exit 1
fi

FEATURE_NAME="$1"
WORKTREE_BASE="$HOME/prg/pykoclaw-worktrees/$FEATURE_NAME"

if [ ! -d "$WORKTREE_BASE" ]; then
    echo "Error: Worktree not found: $WORKTREE_BASE" >&2
    echo "Tip: Run bin/list-worktrees.sh to see active worktrees" >&2
    exit 1
fi

exec "$SCRIPT_DIR/diff-repos.sh" --root="$WORKTREE_BASE" main
