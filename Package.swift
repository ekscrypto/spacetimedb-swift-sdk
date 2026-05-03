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
            name: "SpacetimeDB",
            targets: ["SpacetimeDB"]),
        .library(
            name: "BSATN",
            targets: ["BSATN"]),
        .library(
            name: "SpacetimeDBObservation",
            targets: ["SpacetimeDBObservation"]),
        .executable(
            name: "quickstart-chat",
            targets: ["quickstart-chat"]),
        .executable(
            name: "spacetime-swift",
            targets: ["spacetime-swift"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BSATN"),
        .target(
            name: "SpacetimeDB",
            dependencies: ["BSATN"]),
        .target(
            name: "SpacetimeDBObservation",
            dependencies: ["SpacetimeDB", "BSATN"]),
        .executableTarget(
            name: "quickstart-chat",
            dependencies: ["SpacetimeDB", "BSATN"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]),
        .executableTarget(
            name: "spacetime-swift"),
        .testTarget(
            name: "SpacetimeSwiftCodegenTests",
            dependencies: ["spacetime-swift"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "SpacetimeDBTests",
            dependencies: ["SpacetimeDB"]
        ),
        .testTarget(
            name: "BSATNTests",
            dependencies: ["BSATN"]
        ),
        .testTarget(
            name: "SpacetimeDBObservationTests",
            dependencies: ["SpacetimeDBObservation", "SpacetimeDB", "BSATN"]
        ),
    ]
)