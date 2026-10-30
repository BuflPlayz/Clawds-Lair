// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClawdsLair",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "ClawdsLair", path: "Sources/ClawdsLair"),
        .testTarget(name: "ClawdsLairTests", dependencies: ["ClawdsLair"], path: "Tests/ClawdsLairTests"),
    ],
    swiftLanguageModes: [.v5]
)
