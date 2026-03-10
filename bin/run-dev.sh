#!/bin/sh
# Dev environment launcher for pykoclaw features
# Allocates isolated ports and data directories for development

set -e

# Usage
if [ -z "$1" ]; then
    echo "Usage: $0 <feature-name>"
    echo "  Creates isolated dev environment for a feature"
    exit 1
fi

FEATURE="$1"

# Verify worktree exists
WORKTREE_DIR="$HOME/prg/pykoclaw-worktrees/$FEATURE"
if [ ! -d "$WORKTREE_DIR" ]; then
    echo "Error: Worktree not found at $WORKTREE_DIR"
    exit 1
fi

# Allocate unique port: 8081 + (hash of feature % 100)
# Avoid port 8080 (production) and 8089 (test suite)
PORT_OFFSET=$(echo "$FEATURE" | cksum | cut -d' ' -f1)
PORT_OFFSET=$((PORT_OFFSET % 100))
PORT=$((8081 + PORT_OFFSET))

# Verify port is not 8080 or 8089
if [ "$PORT" -eq 8080 ] || [ "$PORT" -eq 8089 ]; then
    PORT=$((PORT + 1))
fi

# Create temp data directories
PYKOCLAW_DATA="/tmp/pykoclaw-dev-$FEATURE"
MITTO_DIR="/tmp/mitto-dev-$FEATURE"

mkdir -p "$MITTO_DIR/sessions"

# Determine Mitto to use (dev worktree or original)
MITTO_WORKTREE="$HOME/mitto-dev/$FEATURE"
if [ -d "$MITTO_WORKTREE" ]; then
    MITTO_BINARY="$MITTO_WORKTREE/mitto"
else
    MITTO_BINARY="$HOME/mitto/mitto"
fi

# Find pykoclaw binary in worktree
PYKOCLAW_BINARY="$WORKTREE_DIR/.venv/bin/pykoclaw"
if [ ! -f "$PYKOCLAW_BINARY" ]; then
    # Try without venv
    PYKOCLAW_BINARY="$WORKTREE_DIR/pykoclaw"
fi
if [ ! -f "$PYKOCLAW_BINARY" ]; then
    echo "Error: pykoclaw binary not found in $WORKTREE_DIR"
    exit 1
fi

# Create settings.json in MITTO_DIR
cat > "$MITTO_DIR/settings.json" << EOF
{
  "acp_servers": [
    {
      "name": "pykoclaw-dev",
      "command": "$PYKOCLAW_BINARY acp"
    }
  ],
  "web": {
    "host": "127.0.0.1",
    "port": $PORT,
    "external_port": -1
  }
}
EOF

# Print instructions
echo ""
echo "=========================================="
echo "  DEV ENVIRONMENT: $FEATURE"
echo "  PORT: $PORT"
echo "=========================================="
echo ""

echo "--- Dev pykoclaw ACP (Terminal 1) ---"
echo "PYKOCLAW_DATA=$PYKOCLAW_DATA $PYKOCLAW_BINARY acp"
echo ""

echo "--- Dev Mitto (Terminal 2) ---"
echo "MITTO_DIR=$MITTO_DIR $MITTO_BINARY web --port $PORT --dir pykoclaw-dev:$WORKTREE_DIR"
echo ""

echo "--- Data Directories ---"
echo "PYKOCLAW_DATA: $PYKOCLAW_DATA"
echo "MITTO_DIR: $MITTO_DIR"
echo ""
if command -v aoe >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/aoe" ]; then
    echo "--- AoE Sessions ---"
    echo "Group: pykoclaw/$FEATURE"
    echo "Titles:"
    echo "  $FEATURE-root"
    echo "  $FEATURE-pykoclaw"
    echo "  $FEATURE-pykoclaw-acp"
    echo "  $FEATURE-pykoclaw-chat"
    echo "  $FEATURE-pykoclaw-whatsapp"
    echo "  $FEATURE-pykoclaw-messaging"
    echo ""
    echo "Quick check: aoe list"
    echo "Attach: aoe session attach $FEATURE-pykoclaw"
    echo ""
fi
echo "Ready to start!"
