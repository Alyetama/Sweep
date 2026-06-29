// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sweep",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sweep",
            path: "Sources/Sweep"
        )
    ],
    // Built with the Swift 6 toolchain but in the Swift 5 language mode: the app
    // does a lot of FileManager / NSWorkspace / AppKit bridging and shells out to
    // osascript for privileged removals, and we don't want strict-concurrency
    // noise around types that aren't Sendable (NSImage, Process, etc.).
    swiftLanguageModes: [.v5]
)
