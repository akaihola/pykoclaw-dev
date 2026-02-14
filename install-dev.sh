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
echo "Installation complete! Run 'pykoclaw --help' to verify."
