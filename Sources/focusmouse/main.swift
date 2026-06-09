import AppKit
import ApplicationServices
import Darwin
import Foundation
import PrivateFocus

private let pollInterval: TimeInterval = 0.012
private let hoverDelay: TimeInterval = 0.012
private let minimumMouseMovement: CGFloat = 1.0
private let debugLoggingEnabled = ProcessInfo.processInfo.environment["FOCUSMOUSE_DEBUG"] == "1"
private let serviceStartOption = "--start-service"
private let serviceRestartOption = "--restart-service"
private let serviceStopOption = "--stop-service"

private let ignoredApplicationNames = Set([
    "Dock",
    "SystemUIServer",
    "WindowManager"
])

struct WindowCandidate {
    let windowID: UInt32
    let pid: pid_t
    let appName: String
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
                focus(candidate)
                clearPendingCandidate()
            }
        } else {
            pendingCandidate = candidate
            pendingSince = Date()
        }
    }

    private func clearPendingCandidate() {
        pendingCandidate = nil
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
            pid: pid,
            appName: metadata.appName
        )
    }

    private func focus(_ candidate: WindowCandidate) {
        let result = private_focus_window_without_raise(candidate.windowID)
        debug("focus window=\(candidate.windowID) pid=\(candidate.pid) app=\(candidate.appName) result=\(result)")
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

private enum Service {
    static let label = "com.github.uimpa.focusmouse"

    static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(label).plist"
    }

    static var userName: String {
        NSUserName()
    }

    static var serviceTarget: String {
        "gui/\(getuid())/\(label)"
    }

    static var domainTarget: String {
        "gui/\(getuid())"
    }

    static var stdoutPath: String {
        "/tmp/focusmouse_\(userName).out.log"
    }

    static var stderrPath: String {
        "/tmp/focusmouse_\(userName).err.log"
    }

    static func start() -> Int32 {
        do {
            try installPlistIfNeeded()

            if isBootstrapped() {
                return runLaunchctl(["kickstart", serviceTarget])
            }

            let enableStatus = runLaunchctl(["enable", serviceTarget])
            guard enableStatus == EXIT_SUCCESS else {
                return enableStatus
            }

            return runLaunchctl(["bootstrap", domainTarget, plistPath])
        } catch {
            printError("focusmouse: failed to start service: \(error.localizedDescription)")
            return EXIT_FAILURE
        }
    }

    static func restart() -> Int32 {
        runLaunchctl(["kickstart", "-k", serviceTarget])
    }

    static func stop() -> Int32 {
        let bootoutStatus = isBootstrapped()
            ? runLaunchctl(["bootout", domainTarget, plistPath])
            : EXIT_SUCCESS

        let disableStatus = runLaunchctl(["disable", serviceTarget])
        return bootoutStatus == EXIT_SUCCESS ? disableStatus : bootoutStatus
    }

    private static func installPlistIfNeeded() throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: plistPath) else {
            return
        }

        print("service file \(plistPath) is not installed! attempting installation..")
        try fileManager.createDirectory(
            atPath: (plistPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        try plistContents(executablePath: currentExecutablePath())
            .write(toFile: plistPath, atomically: true, encoding: .utf8)
    }

    private static func isBootstrapped() -> Bool {
        runLaunchctl(["print", serviceTarget], quiet: true) == EXIT_SUCCESS
    }

    private static func runLaunchctl(_ arguments: [String], quiet: Bool = false) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        if quiet {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            printError("focusmouse: launchctl \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
            return EXIT_FAILURE
        }
    }

    private static func currentExecutablePath() -> String {
        if let executablePath = Bundle.main.executablePath {
            return executablePath
        }

        let invokedPath = CommandLine.arguments[0] as NSString
        if invokedPath.isAbsolutePath {
            return invokedPath.standardizingPath
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(CommandLine.arguments[0])
            .standardizedFileURL
            .path
    }

    private static func plistContents(executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>

          <key>ProgramArguments</key>
          <array>
            <string>\(xmlEscaped(executablePath))</string>
          </array>

          <key>KeepAlive</key>
          <dict>
            <key>SuccessfulExit</key>
            <false/>
          </dict>

          <key>StandardOutPath</key>
          <string>\(xmlEscaped(stdoutPath))</string>

          <key>StandardErrorPath</key>
          <string>\(xmlEscaped(stderrPath))</string>
        </dict>
        </plist>
        """
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
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

if CommandLine.arguments.count > 1 {
    switch CommandLine.arguments[1] {
    case serviceStartOption:
        exit(Service.start())
    case serviceRestartOption:
        exit(Service.restart())
    case serviceStopOption:
        exit(Service.stop())
    default:
        printError("focusmouse: unknown option \(CommandLine.arguments[1])")
        exit(EXIT_FAILURE)
    }
}

ensureAccessibilityPermission()
FocusMouseDaemon().run()
