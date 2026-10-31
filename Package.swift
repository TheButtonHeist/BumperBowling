// swift-tools-version: 6.4
import PackageDescription

let strictSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "BumperBowling",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BumperBowlingCore", targets: ["BumperBowlingCore"]),
        .library(name: "BumperBowlingTestSupport", targets: ["BumperBowlingTestSupport"]),
        .executable(name: "bumper", targets: ["BumperBowling"]),
    ],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint.git", exact: "0.63.3"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0-prerelease-2026-04-21"),
    ],
    targets: [
        .target(name: "BumperBowlingCore", dependencies: [
            .product(name: "SwiftLintFramework", package: "SwiftLint"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
        ], resources: [.copy("Starter")], swiftSettings: strictSwiftSettings),
        .target(name: "BumperBowlingTestSupport", dependencies: ["BumperBowlingCore"], swiftSettings: strictSwiftSettings),
        .executableTarget(name: "BumperBowling", dependencies: ["BumperBowlingCore"], swiftSettings: strictSwiftSettings),
        .testTarget(name: "BumperBowlingCoreTests", dependencies: ["BumperBowlingCore", "BumperBowlingTestSupport"], swiftSettings: strictSwiftSettings),
        .testTarget(name: "BumperBowlingTestSupportTests", dependencies: ["BumperBowlingCore", "BumperBowlingTestSupport"], swiftSettings: strictSwiftSettings),
    ]
)
