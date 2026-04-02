#!/usr/bin/env bash
set -euo pipefail

# QA Check Script - Runs pytest, make test-go, and make test-js

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYKOCLAW_DEV="$HOME/prg/pykoclaw-worktrees"
MITTO_DIR="$HOME/mitto"

# Parse arguments
FEATURE_NAME="${1:-}"

# Detect feature name from CWD if not provided
if [[ -z "$FEATURE_NAME" ]]; then
    CWD="$(pwd)"
    if [[ "$CWD" == "$PYKOCLAW_DEV"* ]]; then
        FEATURE_NAME="$(basename "$CWD")"
    else
        echo "Error: Could not detect feature name. Please provide as argument or run from a worktree."
        exit 1
    fi
fi

WORKTREE_DIR="$PYKOCLAW_DEV/$FEATURE_NAME"

check_command() {
    local cmd="$1"
    local reason="$2"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    echo "Error: Required command not found: $cmd"
    echo "Reason: $reason"
    return 1
}

preflight_check() {
    local failed=0

    echo "=== Preflight Checks ==="

    if ! check_command "uv" "Needed for pykoclaw pytest execution"; then
        failed=1
    fi

    if ! check_command "make" "Needed for Mitto test-go and test-js targets"; then
        failed=1
    fi

    if ! check_command "go" "Needed by Mitto Go tests"; then
        failed=1
    fi

    if ! check_command "gcc" "Needed by cgo during Mitto Go tests"; then
        failed=1
    fi

    if [[ ! -d "$MITTO_DIR" ]]; then
        echo "Error: Mitto directory not found: $MITTO_DIR"
        failed=1
    fi

    if ! (
        cd "$WORKTREE_DIR"
        uv run --no-sync python -c "import pytest" >/dev/null 2>&1
    ); then
        echo "Error: pytest is not available in worktree environment: $WORKTREE_DIR"
        echo "Fix: cd $WORKTREE_DIR && uv sync --all-packages"
        failed=1
    fi

    if [[ "$failed" -ne 0 ]]; then
        echo ""
        echo "Preflight failed. Fix the issues above and rerun QA."
        return 1
    fi

    echo "Preflight checks passed."
    echo ""
    return 0
}

echo "========================================"
echo "QA Check for feature: $FEATURE_NAME"
echo "========================================"
echo ""

# Verify we're in a worktree
if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo "Error: Worktree directory not found: $WORKTREE_DIR"
    echo "Please provide a valid feature name or run from a worktree."
    exit 1
fi

if ! preflight_check; then
    exit 1
fi

# Function to run tests and capture result
run_test() {
    local test_name="$1"
    local test_dir="$2"
    local test_cmd="$3"
    
    echo "----------------------------------------"
    echo "Running: $test_name"
    echo "Directory: $test_dir"
    echo "Command: $test_cmd"
    echo "----------------------------------------"
    
    if cd "$test_dir" && eval "$test_cmd"; then
        echo "✓ $test_name: PASSED"
        return 0
    else
        echo "✗ $test_name: FAILED"
        return 1
    fi
}

# Track results
PYKOCLAW_RESULT=0
MITTO_GO_RESULT=0
MITTO_JS_RESULT=0

# Run pykoclaw tests
echo ""
echo "=== Running Pykoclaw Tests ==="
if run_test "Pykoclaw pytest" "$WORKTREE_DIR" "uv run pytest"; then
    PYKOCLAW_RESULT=0
else
    PYKOCLAW_RESULT=1
    echo ""
    echo "Warning: Pykoclaw tests failed. Continuing with Mitto tests..."
fi
echo ""

# Run Mitto Go tests
echo ""
echo "=== Running Mitto Go Tests ==="
if run_test "Mitto Go tests" "$MITTO_DIR" "make test-go"; then
    MITTO_GO_RESULT=0
else
    MITTO_GO_RESULT=1
fi
echo ""

# Run Mitto JS tests
echo ""
echo "=== Running Mitto JS Tests ==="
if run_test "Mitto JS tests" "$MITTO_DIR" "make test-js"; then
    MITTO_JS_RESULT=0
else
    MITTO_JS_RESULT=1
fi
echo ""

# Print summary
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Pykoclaw (pytest):    $([ $PYKOCLAW_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo "Mitto Go (test-go):   $([ $MITTO_GO_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo "Mitto JS (test-js):   $([ $MITTO_JS_RESULT -eq 0 ] && echo "PASSED" || echo "FAILED")"
echo "========================================"

# Exit with non-zero if any test failed
if [[ $PYKOCLAW_RESULT -ne 0 ]] || [[ $MITTO_GO_RESULT -ne 0 ]] || [[ $MITTO_JS_RESULT -ne 0 ]]; then
    echo "Overall: FAILED"
    exit 1
fi

echo "Overall: PASSED"
exit 0
