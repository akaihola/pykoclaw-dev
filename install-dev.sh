#!/usr/bin/env bash
set -euo pipefail

# Install pykoclaw with all plugins in editable mode for development
# This allows changes to be reflected without reinstallation

cd "$(dirname "$0")"

echo "Installing pykoclaw with plugins in editable mode..."
uv tool install -e ./pykoclaw \
    --with-editable ./pykoclaw-messaging \
    --with-editable ./pykoclaw-chat \
    --with-editable ./pykoclaw-whatsapp \
    --with-editable ./pykoclaw-acp

echo ""

# Restart services that use pykoclaw so they pick up the new code
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
for svc in mitto-web; do
    if systemctl --user is-active --quiet "$svc" 2>/dev/null; then
        echo "Restarting $svc..."
        systemctl --user restart "$svc"
    fi
done

echo "Installation complete! Run 'pykoclaw --help' to verify."
