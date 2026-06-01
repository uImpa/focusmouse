# FocusMouse

Tiny macOS focus-follows-mouse daemon for personal use.

FocusMouse uses private macOS SkyLight APIs for the actual no-raise focus
operation, plus public APIs for process trust checks and window metadata. That
matches the behavior needed for focus-follows-mouse, but it also means the tool
can break after macOS updates.

## Build

```sh
swift build
```

## Run

```sh
.build/debug/focusmouse
```

When run as a daemon, FocusMouse needs Accessibility permission. Grant
permission to the stable installed binary in System Settings > Privacy &
Security > Accessibility.

## Start at Login

The preferred setup is to install a signed release binary into
`~/.local/bin/focusmouse`, then manage it through launchd:

```sh
sh scripts/install-launch-agent.sh
```

By default, the install script signs with the local code-signing identity named
`focusmouse-cert`. To force a different identity:

```sh
FOCUSMOUSE_SIGNING_IDENTITY="Apple Development: your@email" sh scripts/install-launch-agent.sh
```

After installation, manage the service with:

```sh
focusmouse --start-service
focusmouse --restart-service
focusmouse --stop-service
```

The launch agent lives at:

```text
~/Library/LaunchAgents/com.edwinklasson.focusmouse.plist
```

The service logs to:

```text
/tmp/focusmouse_$USER.out.log
/tmp/focusmouse_$USER.err.log
```

If Accessibility permission is missing, manually add this binary:

```text
/Users/edwinklasson/.local/bin/focusmouse
```

In:

```text
System Settings > Privacy & Security > Accessibility
```

If an older `focusmouse` entry is already present, remove it with the minus
button first, then add the path above again.

Uninstall the launch agent:

```sh
sh scripts/uninstall-launch-agent.sh
```

## Behavior

- Polls the pointer roughly every 12 ms.
- Focuses normal windows after roughly 12 ms of hover.
- Does not intentionally raise windows.
- Does not refocus while a mouse button is held down.
- Does not undo Alt-Tab until the mouse moves.
- Ignores common non-normal targets such as Dock, menu bar, and nonzero-layer
  system windows.
