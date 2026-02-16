#!/usr/bin/env bash
set -euo pipefail

# QA Check Script - Runs pytest, make test-go, and make test-js

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYKOCLAW_DEV="$HOME/pykoclaw-dev"
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
