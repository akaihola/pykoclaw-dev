#!/usr/bin/env bash
set -euo pipefail

# Validate plan files and regenerate BACKLOG.md dashboard.
#
# Run this after any change to .sisyphus/plans/ files.
# Also used by the pre-commit hook as a safety net.
#
# Usage:
#   bin/update-backlog.sh           # validate + regenerate
#   bin/update-backlog.sh --check   # validate only (exit 1 if issues found)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLANS_DIR="$WORKSPACE_ROOT/.sisyphus/plans"
BACKLOG_MD="$WORKSPACE_ROOT/.sisyphus/BACKLOG.md"
QUERY_SCRIPT="$WORKSPACE_ROOT/.sisyphus/query_backlog.py"

CHECK_ONLY=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_ONLY=true
fi

errors=0
warnings=0

# ── Validation ──────────────────────────────────────────────

validate_plans() {
    local file status priority completed

    for file in "$PLANS_DIR"/*.md; do
        [[ -f "$file" ]] || continue
        local basename
        basename="$(basename "$file")"

        # Required: ## Status:
        status="$(grep -oP '^## Status:\s*\K.+' "$file" || true)"
        if [[ -z "$status" ]]; then
            echo "ERROR: $basename — missing '## Status:' field"
            ((errors++))
            continue
        fi

        # Normalize for case-insensitive checks
        local status_lower
        status_lower="$(echo "$status" | tr '[:upper:]' '[:lower:]')"

        # Required for non-Done plans: ## Priority:
        if [[ "$status_lower" != "done" ]]; then
            priority="$(grep -oP '^## Priority:\s*\K\d+' "$file" || true)"
            if [[ -z "$priority" ]]; then
                echo "WARNING: $basename — missing '## Priority:' (status=$status)"
                ((warnings++))
            fi
        fi

        # Required for Done plans: ## Completed: YYYY-MM-DD
        if [[ "$status_lower" == "done" ]]; then
            completed="$(grep -oP '^## Completed:\s*\K\d{4}-\d{2}-\d{2}' "$file" || true)"
            if [[ -z "$completed" ]]; then
                echo "ERROR: $basename — status is Done but missing '## Completed: YYYY-MM-DD'"
                ((errors++))
            else
                # Validate date format (basic: month 01-12, day 01-31)
                if ! echo "$completed" | grep -qP '^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$'; then
                    echo "ERROR: $basename — invalid date format: '$completed' (expected YYYY-MM-DD)"
                    ((errors++))
                fi
            fi
        fi
    done
}

echo "Validating plan files in .sisyphus/plans/..."
validate_plans

if [[ $errors -gt 0 ]]; then
    echo ""
    echo "✗ Validation failed: $errors error(s), $warnings warning(s)"
    exit 1
fi

if [[ $warnings -gt 0 ]]; then
    echo "⚠ $warnings warning(s) found (non-blocking)"
fi

echo "✓ All plan files valid"

# ── Regenerate BACKLOG.md ───────────────────────────────────

if [[ "$CHECK_ONLY" == true ]]; then
    exit 0
fi

echo "Regenerating $BACKLOG_MD..."
"$QUERY_SCRIPT" --format full --output "$BACKLOG_MD"
echo "✓ BACKLOG.md updated"
