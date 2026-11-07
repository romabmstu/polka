// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolkaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PolkaCore", targets: ["PolkaCore"]),
        .library(name: "PolkaSystem", targets: ["PolkaSystem"]),
    ],
    targets: [
        .target(name: "PolkaCore"),
        .target(name: "PolkaSystem", dependencies: ["PolkaCore"]),
        .testTarget(name: "PolkaCoreTests", dependencies: ["PolkaCore"]),
        .testTarget(name: "PolkaSystemTests", dependencies: ["PolkaSystem"]),
    ]
)
