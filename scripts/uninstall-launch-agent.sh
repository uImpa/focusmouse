#!/bin/sh
set -eu

LABEL="com.github.uimpa.focusmouse"
LEGACY_LABEL="com.edwinklasson.focusmouse"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_PLIST_PATH="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
DOMAIN_TARGET="gui/$(id -u)"
SERVICE_TARGET="$DOMAIN_TARGET/$LABEL"
LEGACY_SERVICE_TARGET="$DOMAIN_TARGET/$LEGACY_LABEL"

launchctl bootout "$DOMAIN_TARGET" "$PLIST_PATH" 2>/dev/null || true
launchctl disable "$SERVICE_TARGET" 2>/dev/null || true
launchctl bootout "$DOMAIN_TARGET" "$LEGACY_PLIST_PATH" 2>/dev/null || true
launchctl disable "$LEGACY_SERVICE_TARGET" 2>/dev/null || true
rm -f "$PLIST_PATH" "$LEGACY_PLIST_PATH"

echo "Uninstalled focusmouse launch agent."
