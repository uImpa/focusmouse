#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_BINARY_PATH="$ROOT_DIR/.build/release/focusmouse"
INSTALL_BINARY_PATH="$HOME/.local/bin/focusmouse"
LABEL="com.github.uimpa.focusmouse"
LEGACY_LABEL="com.edwinklasson.focusmouse"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_PLIST_PATH="$HOME/Library/LaunchAgents/$LEGACY_LABEL.plist"
DOMAIN_TARGET="gui/$(id -u)"
SERVICE_TARGET="$DOMAIN_TARGET/$LABEL"
LEGACY_SERVICE_TARGET="$DOMAIN_TARGET/$LEGACY_LABEL"
STDOUT_PATH="/tmp/focusmouse_$(id -un).out.log"
STDERR_PATH="/tmp/focusmouse_$(id -un).err.log"
SIGNING_IDENTITY="${FOCUSMOUSE_SIGNING_IDENTITY:--}"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$(dirname "$PLIST_PATH")" "$(dirname "$INSTALL_BINARY_PATH")"
cp "$BUILD_BINARY_PATH" "$INSTALL_BINARY_PATH"
chmod 755 "$INSTALL_BINARY_PATH"
xattr -d com.apple.quarantine "$INSTALL_BINARY_PATH" 2>/dev/null || true
codesign --force --sign "$SIGNING_IDENTITY" --identifier "$LABEL" "$INSTALL_BINARY_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>

  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_BINARY_PATH</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$STDOUT_PATH</string>

  <key>StandardErrorPath</key>
  <string>$STDERR_PATH</string>
</dict>
</plist>
PLIST

launchctl bootout "$DOMAIN_TARGET" "$LEGACY_PLIST_PATH" 2>/dev/null || true
launchctl disable "$LEGACY_SERVICE_TARGET" 2>/dev/null || true
rm -f "$LEGACY_PLIST_PATH"
launchctl bootout "$DOMAIN_TARGET" "$PLIST_PATH" 2>/dev/null || true
launchctl enable "$SERVICE_TARGET"
launchctl bootstrap "$DOMAIN_TARGET" "$PLIST_PATH"
launchctl kickstart -k "$SERVICE_TARGET"

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
$STDOUT_PATH
$STDERR_PATH
EOF
