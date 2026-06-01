#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_BINARY_PATH="$ROOT_DIR/.build/release/focusmouse"
INSTALL_BINARY_PATH="$HOME/.local/bin/focusmouse"
PLIST_PATH="$HOME/Library/LaunchAgents/com.edwinklasson.focusmouse.plist"
LOG_DIR="$HOME/Library/Logs/focusmouse"
SIGNING_IDENTITY="${FOCUSMOUSE_SIGNING_IDENTITY:-}"

cd "$ROOT_DIR"
swift build -c release

if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY=$(
    security find-identity -v -p codesigning |
      awk -F '"' '/^[[:space:]]*[0-9]+\)/ { print $2; exit }'
  )
fi

if [ -z "$SIGNING_IDENTITY" ]; then
  echo "No valid code signing identity found."
  echo "Create one in Xcode or Keychain Access, then run this script again."
  exit 1
fi

mkdir -p "$(dirname "$PLIST_PATH")" "$(dirname "$INSTALL_BINARY_PATH")" "$LOG_DIR"
cp "$BUILD_BINARY_PATH" "$INSTALL_BINARY_PATH"
chmod 755 "$INSTALL_BINARY_PATH"
xattr -d com.apple.quarantine "$INSTALL_BINARY_PATH" 2>/dev/null || true
codesign --force --sign "$SIGNING_IDENTITY" --identifier com.edwinklasson.focusmouse "$INSTALL_BINARY_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.edwinklasson.focusmouse</string>

  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_BINARY_PATH</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$LOG_DIR/stdout.log</string>

  <key>StandardErrorPath</key>
  <string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

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
$LOG_DIR/stdout.log
$LOG_DIR/stderr.log
EOF
