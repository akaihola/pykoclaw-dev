#!/usr/bin/env bash
set -euo pipefail

# Pull --rebase all repositories in this workspace

cd "$(dirname "$0")"

ok=0
fail=0

for repo in */; do
    [ -d "$repo/.git" ] || continue
    echo "― ${repo%/}"
    if git -C "$repo" pull --rebase 2>&1 | sed 's/^/  /'; then
        ((ok++)) || true
    else
        ((fail++)) || true
    fi
    echo
done

echo "Done: $ok ok, $fail failed."
[ "$fail" -eq 0 ]
