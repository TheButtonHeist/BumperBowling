// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "RepositoryConventions",
    platforms: [.macOS(.v15)],
    products: [.library(name: "BumperRules", targets: ["BumperRules"])],
    dependencies: [.package(name: "BumperBowling", path: "..")],
    targets: [
        .target(name: "BumperRules", dependencies: [.product(name: "BumperBowlingCore", package: "BumperBowling")]),
        .executableTarget(name: "BumperRulesRunner", dependencies: ["BumperRules"]),
        .testTarget(name: "BumperRulesTests", dependencies: [
            "BumperRules",
            .product(name: "BumperBowlingTestSupport", package: "BumperBowling"),
        ]),
    ]
)
