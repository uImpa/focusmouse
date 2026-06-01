import AppKit
import ApplicationServices
import Foundation
import PrivateFocus

private let pollInterval: TimeInterval = 0.012
private let hoverDelay: TimeInterval = 0.012
private let minimumMouseMovement: CGFloat = 1.0
private let debugLoggingEnabled = ProcessInfo.processInfo.environment["FOCUSMOUSE_DEBUG"] == "1"

private let ignoredApplicationNames = Set([
    "Dock",
    "SystemUIServer",
    "WindowManager"
])

struct WindowCandidate {
    let windowID: UInt32
    let ownerConnectionID: Int32
    let pid: pid_t
    let appName: String
    let title: String?
}

private struct WindowMetadata {
    let pid: pid_t
    let layer: Int
    let appName: String
    let title: String?
}

final class FocusMouseDaemon {
    private var pendingCandidate: WindowCandidate?
    private var pendingSince = Date.distantPast
    private var lastMouseLocation: CGPoint?
    private var lastDebugMessage = ""
    private var lastDebugDate = Date.distantPast

    func run() -> Never {
        logAlways("focusmouse running")

        while true {
            autoreleasepool {
                tick()
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private func tick() {
        let mouseMoved = updateMouseMovement()

        guard !isMouseButtonPressed() else {
            clearPendingCandidate()
            return
        }

        guard let candidate = candidateUnderMouse() else {
            clearPendingCandidate()
            return
        }

        guard mouseMoved else {
            clearPendingCandidate()
            return
        }

        if isFrontWindow(candidate) {
            clearPendingCandidate()
            return
        }

        if isSameWindow(candidate, pendingCandidate) {
            if Date().timeIntervalSince(pendingSince) >= hoverDelay {
                _ = focus(candidate)
                clearPendingCandidate()
            }
        } else {
            pendingCandidate = candidate
            pendingSince = Date()
        }
    }

    private func clearPendingCandidate() {
        pendingCandidate = nil
        pendingSince = Date.distantPast
    }

    private func candidateUnderMouse() -> WindowCandidate? {
        var info = PrivateFocusWindowInfo()
        let findResult = private_focus_window_under_mouse(&info)

        guard findResult == 0, info.window_id != 0 else {
            debug("no private window at mouse: \(findResult)")
            return nil
        }

        let windowID = UInt32(info.window_id)
        let pid = pid_t(info.owner_pid)

        guard pid > 0 else {
            debug("window \(windowID) has no owning pid")
            return nil
        }

        guard let metadata = windowMetadata(for: windowID) else {
            debug("window \(windowID) has no CG metadata")
            return nil
        }

        guard metadata.layer == 0 else {
            debug("ignored non-normal layer window=\(windowID) layer=\(metadata.layer) app=\(metadata.appName)")
            return nil
        }

        guard metadata.pid == pid else {
            debug("window \(windowID) pid mismatch private=\(pid) cg=\(metadata.pid)")
            return nil
        }

        guard !ignoredApplicationNames.contains(metadata.appName) else {
            debug("ignored application pid=\(pid) app=\(metadata.appName)")
            return nil
        }

        debug("candidate window=\(windowID) pid=\(pid) app=\(metadata.appName) title=\(metadata.title ?? "<untitled>")")
        return WindowCandidate(
            windowID: windowID,
            ownerConnectionID: info.owner_connection_id,
            pid: pid,
            appName: metadata.appName,
            title: metadata.title
        )
    }

    private func focus(_ candidate: WindowCandidate) -> Bool {
        let result = private_focus_window_without_raise(candidate.windowID)
        debug("focus window=\(candidate.windowID) pid=\(candidate.pid) app=\(candidate.appName) result=\(result)")
        return result == 0
    }

    private func isFrontWindow(_ candidate: WindowCandidate) -> Bool {
        var info = PrivateFocusWindowInfo()
        let result = private_focus_front_window(&info)
        guard result == 0 else {
            debug("front window lookup failed: \(result)")
            return false
        }

        return candidate.windowID == UInt32(info.window_id)
    }

    private func isSameWindow(_ lhs: WindowCandidate?, _ rhs: WindowCandidate?) -> Bool {
        guard let lhs, let rhs else {
            return false
        }

        return lhs.windowID == rhs.windowID
    }

    private func isMouseButtonPressed() -> Bool {
        NSEvent.pressedMouseButtons != 0
    }

    private func updateMouseMovement() -> Bool {
        let location = currentMouseLocation()
        defer {
            lastMouseLocation = location
        }

        guard let previous = lastMouseLocation else {
            return false
        }

        return abs(location.x - previous.x) >= minimumMouseMovement
            || abs(location.y - previous.y) >= minimumMouseMovement
    }

    private func debug(_ message: String) {
        guard debugLoggingEnabled else {
            return
        }

        let now = Date()
        guard message != lastDebugMessage || now.timeIntervalSince(lastDebugDate) >= 1 else {
            return
        }

        lastDebugMessage = message
        lastDebugDate = now
        logAlways("[debug] \(message)")
    }
}

private func currentMouseLocation() -> CGPoint {
    if let event = CGEvent(source: nil) {
        return event.location
    }

    return NSEvent.mouseLocation
}

private func windowMetadata(for windowID: UInt32) -> WindowMetadata? {
    guard let windows = CGWindowListCopyWindowInfo(
        .optionIncludingWindow,
        CGWindowID(windowID)
    ) as? [[String: Any]],
        let window = windows.first else {
        return nil
    }

    guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber,
          let layerNumber = window[kCGWindowLayer as String] as? NSNumber else {
        return nil
    }

    let pid = pid_t(pidNumber.int32Value)
    let appName = window[kCGWindowOwnerName as String] as? String
        ?? NSRunningApplication(processIdentifier: pid)?.localizedName
        ?? "<unknown>"
    let title = window[kCGWindowName as String] as? String

    return WindowMetadata(
        pid: pid,
        layer: layerNumber.intValue,
        appName: appName,
        title: title
    )
}

private func logAlways(_ message: String) {
    print(message)
    fflush(stdout)
}

private func ensureAccessibilityPermission() {
    if AXIsProcessTrusted() {
        return
    }

    let options = [
        "AXTrustedCheckOptionPrompt": true
    ] as CFDictionary

    _ = AXIsProcessTrustedWithOptions(options)

    print("""
    focusmouse needs Accessibility permission.

    Grant it in System Settings > Privacy & Security > Accessibility, then run focusmouse again.
    """)
    exit(EXIT_FAILURE)
}

ensureAccessibilityPermission()
FocusMouseDaemon().run()
