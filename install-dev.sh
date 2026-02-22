#!/usr/bin/env bash
set -euo pipefail

# Install pykoclaw with all plugins in editable mode into ~/.venv/.
# Services use ~/.venv/bin/pykoclaw directly; no separate uv tool install needed.

cd "$(dirname "$0")"

echo "Installing pykoclaw into ~/.venv/ for services and Claude Code skill access..."
uv pip install --python ~/.venv/bin/python \
    -e ./pykoclaw \
    -e ./pykoclaw-messaging \
    -e ./pykoclaw-chat \
    -e ./pykoclaw-whatsapp \
    -e ./pykoclaw-acp \
    -e ./pykoclaw-matrix

echo ""

# Restart pykoclaw services so they pick up the new code
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
for svc in mitto-web pykoclaw-whatsapp pykoclaw-matrix-tyko \
           pykoclaw-scheduler-pipsa pykoclaw-scheduler-tyko pykoclaw-scheduler-vaino; do
    if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
        echo "Restarting $svc..."
        systemctl --user restart "$svc"
    fi
done

echo "Installation complete! Run '~/.venv/bin/pykoclaw --help' to verify."
