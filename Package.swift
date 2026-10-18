// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Mittelklick",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MTBridge", path: "Sources/MTBridge"),
        .executableTarget(name: "Mittelklick", dependencies: ["MTBridge"], path: "Sources/Mittelklick")
    ]
)
