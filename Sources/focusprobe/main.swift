import Foundation
import PrivateFocus

let shouldRaise = CommandLine.arguments.contains("--raise")

var previous = PrivateFocusWindowInfo()
let previousResult = private_focus_front_window(&previous)
if previousResult == 0 {
    print("focusprobe: previous window_id=\(previous.window_id) owner_connection_id=\(previous.owner_connection_id) owner_pid=\(previous.owner_pid)")
} else {
    print("focusprobe: previous lookup failed: \(previousResult)")
}

var info = PrivateFocusWindowInfo()
let findResult = private_focus_window_under_mouse(&info)

guard findResult == 0 else {
    print("focusprobe: failed to find window under mouse: \(findResult)")
    exit(EXIT_FAILURE)
}

print("focusprobe: window_id=\(info.window_id) owner_connection_id=\(info.owner_connection_id) owner_pid=\(info.owner_pid)")

let focusResult = shouldRaise
    ? private_focus_window_with_raise(info.window_id)
    : private_focus_window_without_raise(info.window_id)
guard focusResult == 0 else {
    print("focusprobe: failed to focus window: \(focusResult)")
    exit(EXIT_FAILURE)
}

print("focusprobe: focus call succeeded mode=\(shouldRaise ? "raise" : "no-raise")")
