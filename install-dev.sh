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
    -e ./pykoclaw-matrix \
    -e ./pykoclaw-slack \
    -e ./pykoclaw-vision

echo ""

# Restart pykoclaw/mitto services so they pick up the new code
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
for svc in $(systemctl --user list-units --type=service --state=active \
             --no-legend 'pykoclaw-*' 'mitto-*' | awk '{print $1}'); do
    echo "Restarting $svc..."
    systemctl --user restart "$svc"
done

echo "Installation complete! Run '~/.venv/bin/pykoclaw --help' to verify."
