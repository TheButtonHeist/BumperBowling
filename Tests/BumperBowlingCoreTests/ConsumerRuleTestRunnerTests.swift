import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Consumer rule test runner", .serialized)
struct ConsumerRuleTestRunnerTests {
    @Test
    func `consumer tests use ordinary Swift test defaults`() {
        #expect(ConfigurationLoader.consumerTestArguments(
            packageRoot: URL(fileURLWithPath: "/tmp/Rules")
        ) == ["swift", "test", "--package-path", "/tmp/Rules"])
    }

    @Test func `source-mode consumer tests propagate pass and failure`() throws {
        let root = try makeConsumerRepository(
            testSource: passingConsumerTest,
            at: repositoryRoot().appendingPathComponent(".build/test-fixtures/consumer-source")
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = reusableTestEnvironment()

        let passingStatus = try ConfigurationLoader.runConsumerTests(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: environment
        )
        try failingConsumerTest.write(
            to: root.appendingPathComponent(".bumper/Tests/FixtureRuleTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        let failingStatus = try ConfigurationLoader.runConsumerTests(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: environment
        )

        #expect(passingStatus == 0)
        #expect(failingStatus != 0)
    }

    @Test func `package-mode consumer tests keep package testability`() throws {
        let root = try makePackagedConsumerRepository()

        let status = try ConfigurationLoader.runConsumerTests(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: testEnvironment(for: root)
        )

        #expect(status == 0)
    }

    @Test func `missing consumer tests fail clearly`() throws {
        let root = try makeConsumerRepository(testSource: nil)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try ConfigurationLoader.makeCachedConsumerTestPackage(
                root: root,
                bumperPackageRoot: repositoryRoot(),
                environment: testEnvironment(for: root)
            )
            Issue.record("Expected a missing consumer tests error.")
        } catch let error as BumperError {
            guard case .consumerTestsMissing(let path) = error else {
                Issue.record("Expected consumerTestsMissing, got \(error).")
                return
            }
            #expect(path == root.appendingPathComponent(".bumper/Tests").path)
        }
    }

    @Test func `test-only changes preserve the lint runner cache`() throws {
        let root = try makeConsumerRepository(testSource: passingConsumerTest)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = testEnvironment(for: root)

        let first = try ConfigurationLoader.makeCachedConsumerTestPackage(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: environment
        )
        let unchanged = try ConfigurationLoader.makeCachedConsumerTestPackage(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: environment
        )
        try changedConsumerTest.write(
            to: root.appendingPathComponent(".bumper/Tests/FixtureRuleTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        let changed = try ConfigurationLoader.makeCachedConsumerTestPackage(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: environment
        )

        #expect(first.testSourcesChanged)
        #expect(!unchanged.testSourcesChanged)
        #expect(changed.testSourcesChanged)
        #expect(first.package.root.standardizedFileURL.path == unchanged.package.root.standardizedFileURL.path)
        #expect(unchanged.package.root.standardizedFileURL.path == changed.package.root.standardizedFileURL.path)
    }

    @Test func `source-mode test cache repairs changed bytes and stale files`() throws {
        let root = try makeConsumerRepository(testSource: passingConsumerTest)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = testEnvironment(for: root)

        let first = try ConfigurationLoader.makeCachedConsumerTestPackage(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: environment
        )
        let targetRoot = first.package.root.appendingPathComponent("Tests/BumperRuleTests")
        let copiedTest = targetRoot.appendingPathComponent("ConsumerTests/FixtureRuleTests.swift")
        let staleTest = targetRoot.appendingPathComponent("Stale.swift")
        try "corrupted".write(to: copiedTest, atomically: true, encoding: .utf8)
        try "enum Stale {}".write(to: staleTest, atomically: true, encoding: .utf8)

        let repaired = try ConfigurationLoader.makeCachedConsumerTestPackage(
            root: root,
            bumperPackageRoot: repositoryRoot(),
            environment: environment
        )

        #expect(repaired.testSourcesChanged)
        #expect(try Data(contentsOf: copiedTest) == Data(passingConsumerTest.utf8))
        #expect(!FileManager.default.fileExists(atPath: staleTest.path))
    }
}

private let fixtureConfiguration = """
import BumperBowlingCore

enum FixtureComponent: String, ComponentKey {
    case app
}

let fixtureRule = Rules.files(
    "fixture.always_reports",
    severity: .error,
    summary: "Fixture files always produce one violation."
) { file in
    [RuleFailure(path: file.path, message: "fixture violation")]
}

let bumper = BumperProject {
    Architecture(FixtureComponent.self) {
        Component(.app) {
            Owns("Sources")
        }
    }

    Rules {
        fixtureRule
    }
}
"""

private let passingConsumerTest = """
import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Test func `Fixture rule reports violation`() throws {
    let report = try RuleTestHarness(fixtureRule).evaluate(
        VirtualRepository {
            VirtualSourceFile.swift(
                "Sources/App.swift",
                component: "app",
                source: "struct App {}"
            )
        }
    )

    #expect(report.violations.map { $0.message } == ["fixture violation"])
}
"""

private let failingConsumerTest = """
import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Test func `Fixture rule reports no violations`() throws {
    let report = try RuleTestHarness(fixtureRule).evaluate(
        VirtualRepository {
            VirtualSourceFile.swift(
                "Sources/App.swift",
                component: "app",
                source: "struct App {}"
            )
        }
    )

    #expect(report.violations.isEmpty)
}
"""

private let changedConsumerTest = passingConsumerTest.replacingOccurrences(
    of: "Fixture rule reports violation",
    with: "Fixture rule still reports violation"
)

private let packagedConfiguration = """
import BumperBowlingCore
import BumperRules

enum FixtureComponent: String, ComponentKey {
    case app
}

let bumper = BumperProject {
    Architecture(FixtureComponent.self) {
        Component(.app) {
            Owns("Sources")
        }
    }

    Rules {
        packageFixtureRule
    }
}
"""

private let packagedRuleSource = """
import BumperBowlingCore

public let packageFixtureRule = Rules.files(
    "fixture.package_reports",
    severity: .error,
    summary: "Fixture package files produce one violation."
) { file in
    [RuleFailure(path: file.path, message: "package fixture violation")]
}

let packageInternalSentinel = "visible through @testable"
"""

private let packagedRuleTest = """
import BumperBowlingTestSupport
import Testing
@testable import BumperRules

@Test func `Package tests retain internal visibility`() throws {
    #expect(packageInternalSentinel == "visible through @testable")

    let report = try RuleTestHarness(packageFixtureRule).evaluate(
        VirtualRepository {
            VirtualSourceFile.swift(
                "Sources/App.swift",
                component: "app",
                source: "struct App {}"
            )
        }
    )
    #expect(report.violations.map { $0.message } == ["package fixture violation"])
}
"""

private func makeConsumerRepository(testSource: String?, at fixtureRoot: URL? = nil) throws -> URL {
    let root = fixtureRoot ?? URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try fixtureConfiguration.write(
        to: root.appendingPathComponent(ConfigurationLoader.fileName),
        atomically: true,
        encoding: .utf8
    )

    if let testSource {
        let testURL = root.appendingPathComponent(".bumper/Tests/FixtureRuleTests.swift")
        try FileManager.default.createDirectory(
            at: testURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try testSource.write(to: testURL, atomically: true, encoding: .utf8)
    }
    return root
}

private func makePackagedConsumerRepository() throws -> URL {
    // Keep this fixture at a stable, ignored path so SwiftPM can reuse its
    // scratch directory across local test runs. The fixture sources are
    // rewritten below, so only build products survive between runs.
    let root = repositoryRoot()
        .appendingPathComponent(".build/test-fixtures/consumer-rule-package")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let packageRoot = root.appendingPathComponent(".bumper")
    for relativePath in ["Package.swift", "Package.resolved", "Sources", "Tests", "RuleSpecs"] {
        try? FileManager.default.removeItem(at: packageRoot.appendingPathComponent(relativePath))
    }
    try packagedConfiguration.write(
        to: root.appendingPathComponent(ConfigurationLoader.fileName),
        atomically: true,
        encoding: .utf8
    )
    let packageManifest = """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "BumperRules",
        platforms: [.macOS(.v15)],
        products: [
            .library(name: "BumperRules", targets: ["BumperRules"]),
        ],
        dependencies: [
            .package(name: "BumperBowling", path: \(repositoryRoot().path.debugDescription)),
        ],
        targets: [
            .target(
                name: "BumperRules",
                dependencies: [
                    .product(name: "BumperBowlingCore", package: "BumperBowling"),
                ]
            ),
            .testTarget(
                name: "BumperRulesTests",
                dependencies: [
                    "BumperRules",
                    .product(name: "BumperBowlingTestSupport", package: "BumperBowling"),
                ],
                path: "RuleSpecs"
            ),
        ]
    )
    """
    let files = [
        "Package.swift": packageManifest,
        "Sources/BumperRules/ProjectRules.swift": packagedRuleSource,
        "RuleSpecs/ProjectRulesTests.swift": packagedRuleTest,
    ]
    for (relativePath, contents) in files {
        let destination = packageRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: destination, atomically: true, encoding: .utf8)
    }
    return root
}

private func testEnvironment(for root: URL) -> [String: String] {
    [
        "BUMPER_CACHE_DIR": root.appendingPathComponent("Cache").path,
        "BUMPER_RUNNER_BUILD_CONFIGURATION": "debug",
    ]
}

private func reusableTestEnvironment() -> [String: String] {
    [
        "BUMPER_CACHE_DIR": repositoryRoot()
            .appendingPathComponent(".build/test-fixtures/consumer-cache")
            .path,
        "BUMPER_RUNNER_BUILD_CONFIGURATION": "debug",
    ]
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
