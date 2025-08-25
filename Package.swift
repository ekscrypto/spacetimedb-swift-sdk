// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "spacetimedb-swift-sdk",
    platforms: [
        .macOS(.v12),     // Minimum macOS 12
        .iOS(.v15)        // Minimum iOS 15
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "spacetimedb-swift-sdk",
            targets: ["spacetimedb-swift-sdk"]),
        .library(
            name: "BSATN",
            targets: ["BSATN"]),
        .executable(
            name: "quickstart-chat",
            targets: ["quickstart-chat"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BSATN"),
        .target(
            name: "spacetimedb-swift-sdk",
            dependencies: ["BSATN"]),
        .executableTarget(
            name: "quickstart-chat",
            dependencies: ["spacetimedb-swift-sdk", "BSATN"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]),
        .testTarget(
            name: "spacetimedb-swift-sdkTests",
            dependencies: ["spacetimedb-swift-sdk"]
        ),
        .testTarget(
            name: "BSATNTests",
            dependencies: ["BSATN"]
        ),
    ]
)