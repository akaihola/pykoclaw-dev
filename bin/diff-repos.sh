#!/usr/bin/env bash
# diff-repos.sh [OPTIONS] [REF]
#
# Interactive multi-repo diff browser (fzf + delta).
# Compares all pykoclaw repos against a git reference, showing a live
# syntax-highlighted diff preview for each changed file.
#
# OPTIONS:
#   --root=DIR        Workspace root to scan (default: ~/pykoclaw)
#   --before=TIME     Diff against the last commit before TIME in each repo.
#                     TIME is any format git understands: "2024-01-15 14:00",
#                     "yesterday", "2 hours ago", "2024-01-15T14:00:00".
#
# ARGUMENTS:
#   REF               Git ref to diff against (branch, tag, SHA, HEAD~N …).
#                     If omitted and --before is not given, shows all
#                     uncommitted changes (working tree vs HEAD).
#
# EXAMPLES:
#   bin/diff-repos.sh                              # uncommitted changes
#   bin/diff-repos.sh HEAD~5                       # vs 5 commits ago
#   bin/diff-repos.sh main                         # vs main branch
#   bin/diff-repos.sh --before="2025-01-15 14:00" # vs last commit before that time
#   bin/diff-repos.sh --root=~/pykoclaw-dev/feat main  # feature worktree vs main
#
# KEYS (inside the browser):
#   ↑ / ↓       Navigate file list
#   Enter        Open the selected file's full diff in delta pager
#   Ctrl-A       Open the whole-repo diff for the entry under the cursor
#   Ctrl-C / q  Quit
set -euo pipefail

SUBREPOS=(
    "pykoclaw"
    "pykoclaw-acp"
    "pykoclaw-chat"
    "pykoclaw-whatsapp"
    "pykoclaw-messaging"
    "pykoclaw-matrix"
)

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
ROOT="$HOME/pykoclaw"
BEFORE=""
REF=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root=*)   ROOT="${1#--root=}"; shift ;;
        --root)     ROOT="$2"; shift 2 ;;
        --before=*) BEFORE="${1#--before=}"; shift ;;
        --before)   BEFORE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^set -/p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--root=DIR] [--before=TIME] [REF]" >&2
            exit 1 ;;
        *)
            if [ -n "$REF" ]; then
                echo "Error: unexpected argument '$1' (REF already set to '$REF')" >&2
                exit 1
            fi
            REF="$1"; shift ;;
    esac
done

ROOT="${ROOT%/}"  # strip any trailing slash

if [ ! -d "$ROOT" ]; then
    echo "Error: Root directory not found: $ROOT" >&2
    exit 1
fi

command -v fzf   >/dev/null || { echo "Error: fzf is not installed" >&2; exit 1; }
command -v delta >/dev/null || { echo "Error: delta is not installed" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Resolve the git ref for a given repo directory.
#
# --before mode: find the last commit SHA before the given timestamp.
#   Returns empty string if no commits exist before that time (caller skips).
# REF mode:      return the REF unchanged.
# Default mode:  return "HEAD" (uncommitted changes).
# ---------------------------------------------------------------------------
resolve_ref() {
    local dir="$1"
    if [ -n "$BEFORE" ]; then
        # git log --before filters by author date; this returns the SHA or "".
        git -C "$dir" log --before="$BEFORE" -1 --format="%H" 2>/dev/null || true
    elif [ -n "$REF" ]; then
        echo "$REF"
    else
        echo "HEAD"
    fi
}

# Human-readable diff target label for the header
if [ -n "$BEFORE" ]; then
    DIFF_LABEL="last commit before '$BEFORE' (per repo)"
elif [ -n "$REF" ]; then
    DIFF_LABEL="$REF"
else
    DIFF_LABEL="HEAD  (uncommitted changes)"
fi

# ---------------------------------------------------------------------------
# Collect changed files across all repos.
#
# Each fzf entry is TAB-separated:
#   {1}  DISPLAY  — "%-22s  %s" (repo label + file path) shown in fzf list
#   {2}  DIR      — absolute path to the repo (used in git -C)
#   {3}  FILE     — relative file path within the repo
#   {4}  REF      — resolved git ref for this repo (SHA / branch / HEAD)
#
# The --before case resolves to a different SHA per repo, so it must be
# stored per-entry rather than passed globally to the fzf preview command.
# ---------------------------------------------------------------------------
collect_entries() {
    local label dir ref

    # Workspace root repo
    label="pykoclaw-dev"
    dir="$ROOT"
    if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        ref="$(resolve_ref "$dir")"
        if [ -z "$ref" ]; then
            echo "  [skip] pykoclaw-dev: no commits before '$BEFORE'" >&2
        else
            git -C "$dir" diff --name-only "$ref" 2>/dev/null \
            | while IFS= read -r file; do
                printf '%-22s  %s\t%s\t%s\t%s\n' "$label" "$file" "$dir" "$file" "$ref"
            done
        fi
    fi

    # Subrepos
    for repo in "${SUBREPOS[@]}"; do
        dir="$ROOT/$repo"
        [ -d "$dir" ] || continue
        git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue

        ref="$(resolve_ref "$dir")"
        if [ -z "$ref" ]; then
            echo "  [skip] $repo: no commits before '$BEFORE'" >&2
            continue
        fi

        git -C "$dir" diff --name-only "$ref" 2>/dev/null \
        | while IFS= read -r file; do
            printf '%-22s  %s\t%s\t%s\t%s\n' "$repo" "$file" "$dir" "$file" "$ref"
        done
    done
}

entries="$(collect_entries)"

if [ -z "$entries" ]; then
    echo "No changes found (diff vs $DIFF_LABEL)."
    exit 0
fi

changed_files=$(echo "$entries" | wc -l | tr -d ' ')
root_display="${ROOT/#$HOME/\~}"  # ~/pykoclaw instead of /home/agent/pykoclaw

# ---------------------------------------------------------------------------
# Launch fzf
# ---------------------------------------------------------------------------
echo "$entries" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=1 \
    --header="${root_display}  |  vs ${DIFF_LABEL}  (${changed_files} files)  |  Enter: file diff  Ctrl-A: repo diff" \
    --header-first \
    --preview='git -C {2} diff {4} -- {3} | delta' \
    --preview-window='right:65%:wrap' \
    --bind='enter:execute(git -C {2} diff {4} -- {3} | delta | less -R)' \
    --bind='ctrl-a:execute(git -C {2} diff {4} | delta | less -R)' \
    --bind='ctrl-c:abort' \
    --bind='q:abort'
