// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Swift 6 language mode implies strict concurrency checking and
// InferSendableFromCaptures; warnings are errors everywhere.
let strictSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "BumperBowling",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "BumperBowlingCore", targets: ["BumperBowlingCore"]),
        .library(name: "BumperBowlingTestSupport", targets: ["BumperBowlingTestSupport"]),
        .executable(name: "bumper", targets: ["BumperBowling"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            "602.0.0"..<"604.0.0"
        ),
    ],
    targets: [
        .target(
            name: "BumperBowlingCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .target(
            name: "BumperBowlingTestSupport",
            dependencies: ["BumperBowlingCore"],
            swiftSettings: strictSwiftSettings
        ),
        .executableTarget(
            name: "BumperBowling",
            dependencies: ["BumperBowlingCore"],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "BumperBowlingCoreTests",
            dependencies: [
                "BumperBowlingCore",
                "BumperBowlingTestSupport",
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: strictSwiftSettings
        ),
        .testTarget(
            name: "BumperBowlingTestSupportTests",
            dependencies: [
                "BumperBowlingCore",
                "BumperBowlingTestSupport",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: strictSwiftSettings
        ),
    ]
)
