#!/bin/bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.dandibbert.sorere.host.plist"
DEST_DIR="$HOME/Library/Application Support/Sorere"

launchctl bootout "gui/$UID" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$DEST_DIR"

echo "Sorere Host removed."
