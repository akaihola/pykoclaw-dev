#!/usr/bin/env bash
set -euo pipefail

DEV_ROOT="$HOME/pykoclaw-dev"

if [ ! -d "$DEV_ROOT" ]; then
    echo "No worktree root found at $DEV_ROOT"
    exit 0
fi

echo "Active worktree directories under $DEV_ROOT:"
found=0
for path in "$DEV_ROOT"/*; do
    if [ -d "$path" ]; then
        basename "$path"
        found=1
    fi
done

if [ "$found" -eq 0 ]; then
    echo "(none)"
fi

if command -v aoe >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/aoe" ]; then
    echo ""
    echo "AoE sessions:"
    if command -v aoe >/dev/null 2>&1; then
        aoe list || true
    else
        "$HOME/.cargo/bin/aoe" list || true
    fi
fi
