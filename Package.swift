// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CommandBacktick", platforms: [.macOS(.v14)], products: [
    .executable(name: "CommandBacktick", targets: ["CommandBacktick"])
], targets: [
    .executableTarget(name: "CommandBacktick"),
    .testTarget(name: "CommandBacktickTests", dependencies: ["CommandBacktick"])
])
