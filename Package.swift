// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Locks every target to Swift 6 language mode and opts into the
// `SendableMetatype` upcoming feature so that generic metatype captures
// across actor boundaries (e.g. `R.Type` in a `@Sendable` closure) are
// checked at compile time. Together these match the behaviour of
// `-strict-concurrency=complete` without using `.unsafeFlags`, so
// downstream consumers do not see SwiftPM unsafe-flag warnings.
let strictConcurrency: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("SendableMetatype"),
]

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
            name: "BSATN",
            swiftSettings: strictConcurrency),
        .target(
            name: "SpacetimeDB",
            dependencies: ["BSATN"],
            swiftSettings: strictConcurrency),
        .target(
            name: "SpacetimeDBObservation",
            dependencies: ["SpacetimeDB", "BSATN"],
            swiftSettings: strictConcurrency),
        .executableTarget(
            name: "quickstart-chat",
            dependencies: ["SpacetimeDB", "BSATN"],
            swiftSettings: strictConcurrency + [
                .unsafeFlags(["-parse-as-library"])
            ]),
        .executableTarget(
            name: "spacetime-swift",
            swiftSettings: strictConcurrency),
        .testTarget(
            name: "SpacetimeSwiftCodegenTests",
            dependencies: ["spacetime-swift"],
            resources: [.process("Fixtures")],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "SpacetimeDBTests",
            dependencies: ["SpacetimeDB"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "BSATNTests",
            dependencies: ["BSATN"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "SpacetimeDBObservationTests",
            dependencies: ["SpacetimeDBObservation", "SpacetimeDB", "BSATN"],
            swiftSettings: strictConcurrency
        ),
    ]
)