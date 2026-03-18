#!/usr/bin/env bash
set -euo pipefail

# Rebase all feature worktrees (or a single named one) onto the latest local main.
#
# For each feature worktree, every subrepo whose checked-out branch is NOT main
# is rebased onto main.  Repos already up to date are skipped.  On conflict the
# rebase is aborted and the repo is flagged as failed so work can continue with
# the rest.
#
# Usage:
#   bin/rebase-worktrees.sh               # rebase all features
#   bin/rebase-worktrees.sh <feature>     # rebase one feature
#   bin/rebase-worktrees.sh --fetch       # fetch origin first, then rebase all
#   bin/rebase-worktrees.sh --fetch <f>   # fetch + rebase one feature

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MAIN_CHECKOUT="$(git -C "$WORKSPACE_ROOT" worktree list --porcelain \
    | awk '/^worktree/{path=$2} /^branch refs\/heads\/main/{print path; exit}')"
if [ -z "$MAIN_CHECKOUT" ]; then
    echo "Error: Could not determine main checkout path (no worktree on branch 'main')" >&2
    exit 1
fi

# Auto-detect subrepos: every subdirectory with both pyproject.toml and .git.
mapfile -t SUBREPOS < <(
    for d in "$MAIN_CHECKOUT"/*/; do
        [[ -f "${d}pyproject.toml" ]] && [[ -e "${d}.git" ]] && basename "$d"
    done
)

WORKTREES_BASE="$HOME/prg/pykoclaw-worktrees"

print_status() { echo -e "${1}${2}${NC}"; }
print_header() { echo -e "\n${CYAN}════════════════════════════════════════${NC}"; echo -e "${CYAN}${1}${NC}"; echo -e "${CYAN}════════════════════════════════════════${NC}"; }

# --- Parse args ---
DO_FETCH=0
FEATURE_FILTER=""
for arg in "$@"; do
    case "$arg" in
        --fetch) DO_FETCH=1 ;;
        -*) echo "Unknown option: $arg" >&2; echo "Usage: $0 [--fetch] [feature]" >&2; exit 1 ;;
        *)  FEATURE_FILTER="$arg" ;;
    esac
done

# --- Optional fetch ---
if [[ "$DO_FETCH" -eq 1 ]]; then
    print_header "Fetching origin"
    # Fetch in every canonical subrepo and the root
    for repo in "$MAIN_CHECKOUT" "${SUBREPOS[@]/#/$MAIN_CHECKOUT/}"; do
        rel="${repo#"$MAIN_CHECKOUT"/}"
        [ "$rel" = "$MAIN_CHECKOUT" ] && rel="(root)"
        if git -C "$repo" fetch origin 2>&1 | grep -q '.'; then
            print_status "$GREEN" "  ✓ fetched $rel"
        else
            print_status "$YELLOW" "  - $rel: nothing new"
        fi
    done
fi

# --- Determine features to process ---
if [[ -n "$FEATURE_FILTER" ]]; then
    if [[ ! -d "$WORKTREES_BASE/$FEATURE_FILTER" ]]; then
        echo "Error: Worktree not found: $WORKTREES_BASE/$FEATURE_FILTER" >&2
        exit 1
    fi
    FEATURES=("$FEATURE_FILTER")
else
    mapfile -t FEATURES < <(ls "$WORKTREES_BASE" 2>/dev/null)
fi

if [[ ${#FEATURES[@]} -eq 0 ]]; then
    print_status "$YELLOW" "No feature worktrees found under $WORKTREES_BASE"
    exit 0
fi

# --- Per-feature counters ---
TOTAL_REBASED=0
TOTAL_SKIPPED=0
TOTAL_FAILED=0
declare -A FAILED_REPOS   # FAILED_REPOS[feature/repo]="reason"

# --- Rebase one repo path onto main ---
# Returns 0=rebased, 1=skipped (up to date), 2=failed
rebase_repo() {
    local path="$1"
    local label="$2"

    # Must have a valid HEAD
    if ! git -C "$path" rev-parse --verify HEAD >/dev/null 2>&1; then
        print_status "$YELLOW" "  - $label: not a git repo, skipping"
        return 1
    fi

    local branch
    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Skip repos sitting on main
    if [[ "$branch" == "main" ]]; then
        print_status "$YELLOW" "  - $label: on main, skipping"
        return 1
    fi

    local behind ahead
    behind=$(git -C "$path" rev-list --count HEAD..main 2>/dev/null || echo 0)
    ahead=$(git -C "$path"  rev-list --count main..HEAD 2>/dev/null || echo 0)

    if [[ "$behind" -eq 0 ]]; then
        print_status "$GREEN" "  ✓ $label ($branch): already up to date"
        return 1  # skipped
    fi

    print_status "$YELLOW" "  ↑ $label ($branch): $ahead ahead, $behind behind — rebasing..."

    local output exit_code
    output=$(git -C "$path" rebase main 2>&1) && exit_code=0 || exit_code=$?

    if [[ "$exit_code" -eq 0 ]]; then
        echo "$output" | grep -v '^$' | head -5 | sed 's/^/    /'
        print_status "$GREEN" "  ✓ $label: rebased OK"
        return 0
    else
        echo "$output" | head -10 | sed 's/^/    /'
        print_status "$RED" "  ✗ $label: conflict — aborting"
        git -C "$path" rebase --abort 2>/dev/null || true
        return 2
    fi
}

# --- Main loop ---
for feature in "${FEATURES[@]}"; do
    wt_base="$WORKTREES_BASE/$feature"
    [[ -d "$wt_base" ]] || continue

    print_header "FEATURE: $feature"

    feat_rebased=0
    feat_skipped=0
    feat_failed=0

    # Root worktree (pykoclaw-dev itself)
    if [[ -e "$wt_base/.git" ]]; then
        result=0
        rebase_repo "$wt_base" "(root)" || result=$?
        case $result in
            0) feat_rebased=$(( feat_rebased + 1 )) ;;
            1) feat_skipped=$(( feat_skipped + 1 )) ;;
            2) feat_failed=$(( feat_failed + 1 )); FAILED_REPOS["$feature/(root)"]="conflict" ;;
        esac
    fi

    # Subrepos
    for repo in "${SUBREPOS[@]}"; do
        wt_repo="$wt_base/$repo"
        [[ -e "$wt_repo/.git" ]] || continue

        result=0
        rebase_repo "$wt_repo" "$repo" || result=$?
        case $result in
            0) feat_rebased=$(( feat_rebased + 1 )) ;;
            1) feat_skipped=$(( feat_skipped + 1 )) ;;
            2) feat_failed=$(( feat_failed + 1 )); FAILED_REPOS["$feature/$repo"]="conflict" ;;
        esac
    done

    echo ""
    [[ $feat_rebased -gt 0 ]] && print_status "$GREEN"  "  → rebased: $feat_rebased"
    [[ $feat_skipped -gt 0 ]] && print_status "$YELLOW" "  → up to date: $feat_skipped"
    [[ $feat_failed  -gt 0 ]] && print_status "$RED"    "  → failed: $feat_failed"

    TOTAL_REBASED=$(( TOTAL_REBASED + feat_rebased ))
    TOTAL_SKIPPED=$(( TOTAL_SKIPPED + feat_skipped ))
    TOTAL_FAILED=$(( TOTAL_FAILED  + feat_failed  ))
done

# --- Final summary ---
print_header "SUMMARY"
print_status "$GREEN"  "  Rebased:       $TOTAL_REBASED"
print_status "$YELLOW" "  Up to date:    $TOTAL_SKIPPED"
[[ $TOTAL_FAILED -gt 0 ]] && print_status "$RED" "  Failed:        $TOTAL_FAILED"

if [[ ${#FAILED_REPOS[@]} -gt 0 ]]; then
    echo ""
    print_status "$RED" "  Repos with conflicts (need manual rebase):"
    for key in "${!FAILED_REPOS[@]}"; do
        print_status "$RED" "    $key"
    done
fi

echo ""
if [[ $TOTAL_FAILED -eq 0 ]]; then
    print_status "$GREEN" "All done."
else
    print_status "$RED" "Some rebases failed. Fix conflicts manually, then re-run."
    exit 1
fi
