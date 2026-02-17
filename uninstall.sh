#!/bin/bash
# Record Toggle uninstaller
set -euo pipefail

echo ""
echo "  Record Toggle Uninstaller"
echo "  ========================="
echo ""

read -p "This will remove Record Toggle. Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Remove installed script
if [ -f "/usr/local/bin/record-toggle" ]; then
    if [ -w "/usr/local/bin" ]; then
        rm -f "/usr/local/bin/record-toggle"
    else
        sudo rm -f "/usr/local/bin/record-toggle"
    fi
    echo "[ok] Removed /usr/local/bin/record-toggle"
fi

# Remove Automator workflow
WORKFLOW="$HOME/Library/Services/Record Toggle.workflow"
if [ -d "$WORKFLOW" ]; then
    rm -rf "$WORKFLOW"
    echo "[ok] Removed Quick Action workflow"
fi

# Remove old workflow name if exists
OLD_WORKFLOW="$HOME/Library/Services/Interview Record Toggle.workflow"
if [ -d "$OLD_WORKFLOW" ]; then
    rm -rf "$OLD_WORKFLOW"
    echo "[ok] Removed old Quick Action workflow"
fi

# Remove config
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/record-toggle"
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo "[ok] Removed config at $CONFIG_DIR"
fi

# Remove venv
VENV_DIR="$HOME/.local/share/record-toggle"
if [ -d "$VENV_DIR" ]; then
    rm -rf "$VENV_DIR"
    echo "[ok] Removed Whisper venv at $VENV_DIR"
fi

# Remove temp files
if [ -d "/tmp/record-toggle" ]; then
    rm -rf "/tmp/record-toggle"
    echo "[ok] Removed temp files"
fi

echo ""
echo "  Uninstall complete."
echo "  Note: Remove the keyboard shortcut manually in System Settings."
echo ""
