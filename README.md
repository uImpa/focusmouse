# FocusMouse

Tiny macOS focus-follows-mouse daemon using public Accessibility APIs only.

## Build

```sh
swift build
```

## Run

```sh
.build/debug/focusmouse
```

On first run, macOS should prompt for Accessibility permission. Grant permission
in System Settings > Privacy & Security > Accessibility, then run the daemon
again.

## Start at Login

Start the current `focusmouse` binary as a per-user launchd service:

```sh
.build/debug/focusmouse --start-service
```

If the launch agent plist does not exist yet, this creates:

```text
~/Library/LaunchAgents/com.edwinklasson.focusmouse.plist
```

The generated service runs the same `focusmouse` binary with no arguments.
Logs are written to:

```text
/tmp/focusmouse_$USER.out.log
/tmp/focusmouse_$USER.err.log
```

Restart or stop the service:

```sh
.build/debug/focusmouse --restart-service
.build/debug/focusmouse --stop-service
```

Install a per-user launch agent:

```sh
sh scripts/install-launch-agent.sh
```

This builds the release binary, copies it to `~/.local/bin/focusmouse`, signs it
with the first valid code-signing identity in your login keychain, and registers
that stable copy with `launchd`.

To force a specific signing identity:

```sh
FOCUSMOUSE_SIGNING_IDENTITY="Apple Development: your@email" sh scripts/install-launch-agent.sh
```

If Accessibility permission is still missing, manually add this binary in System
Settings > Privacy & Security > Accessibility:

```text
/Users/edwinklasson/.local/bin/focusmouse
```

If an older `focusmouse` entry is already present, remove it with the minus
button first, then add the path above again.

Uninstall the launch agent:

```sh
sh scripts/uninstall-launch-agent.sh
```

## Behavior

- Polls the pointer roughly every 75 ms.
- Focuses normal windows after roughly 120 ms of hover.
- Does not intentionally raise windows.
- Does not refocus while a mouse button is held down.
- Ignores common non-normal targets such as Dock, menu bar, dialogs, sheets,
  floating windows, and minimized windows.
