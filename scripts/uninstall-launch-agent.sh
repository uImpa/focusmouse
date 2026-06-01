#!/bin/sh
set -eu

PLIST_PATH="$HOME/Library/LaunchAgents/com.edwinklasson.focusmouse.plist"
LABEL="com.edwinklasson.focusmouse"
DOMAIN_TARGET="gui/$(id -u)"
SERVICE_TARGET="$DOMAIN_TARGET/$LABEL"

launchctl bootout "$DOMAIN_TARGET" "$PLIST_PATH" 2>/dev/null || true
launchctl disable "$SERVICE_TARGET" 2>/dev/null || true
rm -f "$PLIST_PATH"

echo "Uninstalled focusmouse launch agent."
