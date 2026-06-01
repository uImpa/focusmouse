// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusMouse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "focusmouse", targets: ["focusmouse"]),
        .executable(name: "focusprobe", targets: ["focusprobe"])
    ],
    targets: [
        .target(name: "PrivateFocus"),
        .executableTarget(
            name: "focusmouse",
            dependencies: ["PrivateFocus"]
        ),
        .executableTarget(
            name: "focusprobe",
            dependencies: ["PrivateFocus"]
        )
    ]
)
