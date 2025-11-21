// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetworkBatcher",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "NetworkBatcher",
            targets: ["NetworkBatcher"]
        ),
        // Optional analytics wrappers
        .library(
            name: "NetworkBatcherAnalytics",
            targets: ["NetworkBatcherAnalytics"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NetworkBatcher",
            dependencies: [],
            path: "Sources/NetworkBatcher"
        ),
        .target(
            name: "NetworkBatcherAnalytics",
            dependencies: ["NetworkBatcher"],
            path: "Sources/NetworkBatcherAnalytics"
        ),
        .testTarget(
            name: "NetworkBatcherTests",
            dependencies: ["NetworkBatcher"],
            path: "Tests/NetworkBatcherTests"
        ),
    ]
)
