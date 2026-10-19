// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmoothScroll",
    platforms: [.macOS("27.0")],
    targets: [
        // Pure animation/math logic, no AppKit — fully unit-tested.
        .target(name: "SmoothScrollCore"),
        // Menu bar app: event tap, display link, settings UI.
        .executableTarget(
            name: "SmoothScroll",
            dependencies: ["SmoothScrollCore"]
        ),
        .testTarget(
            name: "SmoothScrollCoreTests",
            dependencies: ["SmoothScrollCore"]
        ),
    ]
)
