#!/usr/bin/env bash
set -euo pipefail

# Install pykoclaw into the testi-dedicated virtualenv (~/.testi-venv).
# The testi services (pykoclaw-scheduler-testi, pykoclaw-matrix-testi,
# mitto-web-testi) all use ~/.testi-venv/bin/pykoclaw so that feature
# branches can be deployed there for testing without touching the
# production ~/.venv.
#
# Usage:
#   ./install-testi.sh            # install from this workspace (main)
#   ./install-testi.sh <worktree> # install from ~/prg/pykoclaw-worktrees/<worktree>
#
# After install the testi services are restarted automatically.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -n "${1:-}" ]]; then
    SOURCE_DIR="$HOME/prg/pykoclaw-worktrees/$1"
    if [[ ! -d "$SOURCE_DIR" ]]; then
        echo "Error: Worktree not found: $SOURCE_DIR" >&2
        exit 1
    fi
    echo "Installing from worktree: $SOURCE_DIR"
else
    SOURCE_DIR="$SCRIPT_DIR"
    echo "Installing from workspace: $SOURCE_DIR"
fi

TESTI_VENV="$HOME/.testi-venv"

if [[ ! -x "$TESTI_VENV/bin/python" ]]; then
    echo "Creating ~/.testi-venv ..."
    uv venv --python python3.13 "$TESTI_VENV"
fi

echo "Installing pykoclaw packages into $TESTI_VENV ..."
uv pip install --python "$TESTI_VENV/bin/python" \
    -e "$SOURCE_DIR/pykoclaw" \
    -e "$SOURCE_DIR/pykoclaw-messaging" \
    -e "$SOURCE_DIR/pykoclaw-chat" \
    -e "$SOURCE_DIR/pykoclaw-whatsapp" \
    -e "$SOURCE_DIR/pykoclaw-acp" \
    -e "$SOURCE_DIR/pykoclaw-matrix" \
    -e "$SOURCE_DIR/pykoclaw-slack" \
    -e "$SOURCE_DIR/pykoclaw-vision"
    # pykoclaw-slack: installed above but has no testi service — coleaders only

echo ""

# Restart only the testi services so production is unaffected
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
for svc in pykoclaw-scheduler-testi pykoclaw-matrix-testi mitto-web-testi; do
    if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
        echo "Restarting $svc ..."
        systemctl --user restart "$svc"
    else
        echo "Skipping $svc (not active)"
    fi
done

echo ""
echo "Testi install complete. Run '$TESTI_VENV/bin/pykoclaw --help' to verify."
