#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_BINARY_PATH="$ROOT_DIR/.build/release/focusmouse"
INSTALL_BINARY_PATH="$HOME/.local/bin/focusmouse"
LABEL="com.github.uimpa.focusmouse"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN_TARGET="gui/$(id -u)"
SIGNING_IDENTITY="${FOCUSMOUSE_SIGNING_IDENTITY:--}"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$(dirname "$INSTALL_BINARY_PATH")"
cp "$BUILD_BINARY_PATH" "$INSTALL_BINARY_PATH"
chmod 755 "$INSTALL_BINARY_PATH"
xattr -d com.apple.quarantine "$INSTALL_BINARY_PATH" 2>/dev/null || true
codesign --force --sign "$SIGNING_IDENTITY" --identifier "$LABEL" "$INSTALL_BINARY_PATH"

launchctl bootout "$DOMAIN_TARGET" "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"
"$INSTALL_BINARY_PATH" --start-service

cat <<EOF
Installed launch agent:
$PLIST_PATH

Binary:
$INSTALL_BINARY_PATH

Signed with:
$SIGNING_IDENTITY

If Accessibility permission is still missing, add the binary above in:
System Settings > Privacy & Security > Accessibility

If an older focusmouse entry already exists there, remove it first, then add
the binary above again.

Logs:
/tmp/focusmouse_$(id -un).out.log
/tmp/focusmouse_$(id -un).err.log
EOF
