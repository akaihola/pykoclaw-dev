#!/usr/bin/env bash
set -euo pipefail

# bin/new-plugin.sh <feature> <plugin-name>
#
# Creates a new plugin subrepo within an existing feature worktree.
#
# This is the ONLY correct way to add a new package during feature development.
# NEVER run `git init` directly in the feature worktree directory — the canonical
# repo MUST be created in the main checkout first, and then a worktree is added
# from it.  Violating this causes `merge-feature.sh` to detect the repo as
# "standalone" and auto-adopt it, which works but is slower and error-prone.
#
# What this script does:
#   1. Create canonical repo at ~/pykoclaw/<plugin-name>/ with initial commit on main
#   2. Create feature/<feature> branch pointing to that commit
#   3. Add git worktree at ~/pykoclaw-dev/<feature>/<plugin-name>/ (on feature branch)
#   4. Add the plugin to the workspace pyproject.toml on the feature branch and commit
#   5. Run uv sync --all-packages in the worktree so the new package is available
#   6. Create AoE session (if aoe is available)
#
# Usage:
#   bin/new-plugin.sh <feature> <plugin-name>
#
#   feature:     existing feature worktree name (e.g. my-feature)
#   plugin-name: new package directory name     (e.g. pykoclaw-myplugin)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MAIN_CHECKOUT="$(git -C "$WORKSPACE_ROOT" worktree list --porcelain \
    | awk '/^worktree/{path=$2} /^branch refs\/heads\/main/{print path; exit}')"
if [[ -z "$MAIN_CHECKOUT" ]]; then
    echo "Error: Could not determine main checkout (no worktree on branch 'main')" >&2
    exit 1
fi

if [[ -z "${1:-}" || -z "${2:-}" ]]; then
    echo "Usage: $0 <feature> <plugin-name>" >&2
    echo ""
    echo "  feature:     name of the existing feature worktree (e.g. my-feature)" >&2
    echo "  plugin-name: new package directory name (e.g. pykoclaw-myplugin)" >&2
    echo ""
    echo "Example: $0 my-feature pykoclaw-myplugin" >&2
    exit 1
fi

FEATURE="$1"
PLUGIN="$2"
BRANCH="feature/$FEATURE"
CANONICAL="$MAIN_CHECKOUT/$PLUGIN"
WORKTREE_BASE="$HOME/pykoclaw-dev/$FEATURE"
WORKTREE="$WORKTREE_BASE/$PLUGIN"
PKG_NAME="${PLUGIN//-/_}"

# --- Validate ---
[[ -d "$WORKTREE_BASE" ]] || {
    echo "Error: Feature worktree not found: $WORKTREE_BASE" >&2
    echo "       Run: bin/create-worktree.sh $FEATURE" >&2
    exit 1
}
[[ ! -d "$CANONICAL" ]] || {
    echo "Error: Plugin already exists in main checkout: $CANONICAL" >&2
    exit 1
}
[[ ! -e "$WORKTREE" ]] || {
    echo "Error: Path already exists in feature worktree: $WORKTREE" >&2
    exit 1
}

echo "Creating new plugin: $PLUGIN"
echo "  Feature branch:  $BRANCH"
echo "  Canonical repo:  $CANONICAL"
echo "  Worktree:        $WORKTREE"
echo ""

# --- 1. Init canonical repo with an initial commit on main ---
mkdir -p "$CANONICAL"
git -C "$CANONICAL" init --initial-branch main

# Minimal pyproject.toml stub — developer fills in details
cat > "$CANONICAL/pyproject.toml" <<EOF
[project]
name = "$PLUGIN"
version = "0.1.0"
description = ""
requires-python = ">=3.12"
dependencies = ["pykoclaw"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/$PKG_NAME"]

[tool.pytest.ini_options]
asyncio_mode = "strict"
testpaths = ["tests"]
EOF

mkdir -p "$CANONICAL/src/$PKG_NAME" "$CANONICAL/tests"
touch "$CANONICAL/src/$PKG_NAME/__init__.py"
touch "$CANONICAL/tests/__init__.py"

git -C "$CANONICAL" add .
git -C "$CANONICAL" commit -m "chore: initial scaffold for $PLUGIN"
echo "  ✓ Created canonical repo on main"

# --- 2. Create feature branch ---
git -C "$CANONICAL" branch "$BRANCH"
echo "  ✓ Created branch $BRANCH"

# --- 3. Add worktree on feature branch ---
git -C "$CANONICAL" worktree add "$WORKTREE" "$BRANCH"
echo "  ✓ Added worktree at $WORKTREE"

# --- 4. Add to workspace pyproject.toml on the feature branch ---
# Only update the feature branch's pyproject.toml; merge-feature.sh carries
# this to main when the feature is merged.  Updating main here would risk a
# conflict when the root workspace is merged.
FEATURE_PYPROJECT="$WORKTREE_BASE/pyproject.toml"
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
" "$FEATURE_PYPROJECT" "$PLUGIN"

if ! git -C "$WORKTREE_BASE" diff --quiet -- pyproject.toml 2>/dev/null; then
    git -C "$WORKTREE_BASE" add pyproject.toml
    git -C "$WORKTREE_BASE" commit -m "chore: add $PLUGIN to workspace members"
    echo "  ✓ Updated workspace pyproject.toml on feature branch"
fi

# --- 5. uv sync ---
echo "  Running uv sync --all-packages ..."
(cd "$WORKTREE_BASE" && uv sync --all-packages 2>&1 | grep -E "^\+|^Installed|warning" || true)
echo "  ✓ uv sync done"

# --- 6. AoE session ---
AOE_BIN=""
if command -v aoe >/dev/null 2>&1; then
    AOE_BIN="$(command -v aoe)"
elif [[ -x "$HOME/.cargo/bin/aoe" ]]; then
    AOE_BIN="$HOME/.cargo/bin/aoe"
fi

if [[ -n "$AOE_BIN" ]]; then
    AOE_GROUP="pykoclaw/$FEATURE"
    SESSION_TITLE="$FEATURE-$PLUGIN"
    if "$AOE_BIN" add "$WORKTREE" --title "$SESSION_TITLE" \
            --group "$AOE_GROUP" --cmd opencode >/dev/null 2>&1; then
        echo "  ✓ Created AoE session: $SESSION_TITLE"
    else
        echo "  (AoE session not created — group may not exist yet)"
    fi
fi

echo ""
echo "Plugin '$PLUGIN' is ready."
echo ""
echo "  cd $WORKTREE"
echo "  # ... develop the plugin ..."
echo ""
echo "When done, merge as usual:"
echo "  bin/merge-feature.sh $FEATURE"
echo "  ./install-dev.sh"
echo "  bin/cleanup-worktree.sh $FEATURE"
