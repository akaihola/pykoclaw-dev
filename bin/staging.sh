#!/usr/bin/env bash
set -euo pipefail

# Launch a staging pykoclaw ACP server via Mitto web for user review.
# Uses isolated data directory so staging doesn't touch production.
# Ctrl+C stops both Mitto and pykoclaw.

if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <feature-name>" >&2
    echo "  Launches Mitto web + pykoclaw ACP from a feature worktree" >&2
    exit 1
fi

FEATURE="$1"
WORKTREE_DIR="$HOME/prg/pykoclaw-worktrees/$FEATURE"

if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo "Error: Worktree not found at $WORKTREE_DIR" >&2
    exit 1
fi

# --- Locate binaries ---

MITTO_BINARY="$HOME/mitto/mitto"
if [[ ! -x "$MITTO_BINARY" ]]; then
    echo "Error: Mitto not found at $MITTO_BINARY" >&2
    exit 1
fi

# --- Allocate port (hash-based, avoids 8080 production and 8089 test) ---

PORT_OFFSET=$(echo "$FEATURE" | cksum | cut -d' ' -f1)
PORT_OFFSET=$((PORT_OFFSET % 100))
PORT=$((8081 + PORT_OFFSET))
if [[ "$PORT" -eq 8080 ]] || [[ "$PORT" -eq 8089 ]]; then
    PORT=$((PORT + 1))
fi

# --- Isolated data directories ---

export PYKOCLAW_DATA="/tmp/pykoclaw-dev-$FEATURE"
export MITTO_DIR="/tmp/mitto-dev-$FEATURE"
MITTO_CONFIG="$MITTO_DIR/config.yaml"
mkdir -p "$PYKOCLAW_DATA" "$MITTO_DIR/sessions"

# --- Generate Mitto config pointing at worktree's pykoclaw ---
# Use `uv run` from worktree so it picks up the feature branch code.

cat > "$MITTO_CONFIG" << EOF
acp:
  - pykoclaw-dev:
      command: uv run --directory $WORKTREE_DIR pykoclaw acp
      env:
        PYKOCLAW_DATA: $PYKOCLAW_DATA
EOF

echo ""
echo "=========================================="
echo "  STAGING: $FEATURE"
echo "  http://127.0.0.1:$PORT"
echo "=========================================="
echo "  Worktree:  $WORKTREE_DIR"
echo "  Data:      $PYKOCLAW_DATA"
echo "  Mitto:     $MITTO_DIR"
echo ""
echo "  Ctrl+C to stop."
echo "=========================================="
echo ""

# --- Launch Mitto (it spawns pykoclaw ACP as a subprocess) ---

exec "$MITTO_BINARY" web \
    --config "$MITTO_CONFIG" \
    --port "$PORT" \
    --dir "pykoclaw-dev:$WORKTREE_DIR"
