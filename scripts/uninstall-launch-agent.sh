#!/bin/sh
set -eu

PLIST_PATH="$HOME/Library/LaunchAgents/com.edwinklasson.focusmouse.plist"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"

echo "Uninstalled focusmouse launch agent."
