import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Project runner policy")
struct ProjectRunnerPolicyTests {
    @Test
    func generatedPackagesUseSwiftSixWithoutRedundantUpcomingFeatures() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        try "let bumper = BumperProject(rules: [])".write(
            to: configurationURL,
            atomically: true,
            encoding: .utf8
        )
        let package = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: repositoryRoot(),
            environment: [:]
        )
        let manifest = try String(
            contentsOf: package.root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(manifest.components(separatedBy: ".swiftLanguageMode(.v6)").count == 3)
        #expect(!manifest.contains("enableUpcomingFeature"))
    }

    @Test
    func cachedRunnerBuildsInReleaseConfigurationByDefault() throws {
        let configuration = try ConfigurationLoader.projectRunnerBuildConfiguration(environment: [:])
        let arguments = ConfigurationLoader.cachedRunnerBuildArguments(
            packageRoot: URL(fileURLWithPath: "/tmp/cache/abc"),
            buildConfiguration: configuration
        )

        #expect(configuration == "release")
        #expect(arguments.contains("build"))
        #expect(arguments.contains("release"))
        #expect(arguments.contains("BumperProjectRunner"))
        #expect(!arguments.contains("debug"))
    }

    @Test
    func cachedExecutablePathMatchesBuildConfiguration() {
        let executable = ConfigurationLoader.cachedRunnerExecutableURL(
            in: URL(fileURLWithPath: "/tmp/cache/abc"),
            productName: "BumperProjectRunner",
            buildConfiguration: "release"
        )

        #expect(executable.path == "/tmp/cache/abc/.build/release/BumperProjectRunner")
    }

    @Test
    func runnerBuildConfigurationHonorsSupportedOverride() throws {
        let configuration = try ConfigurationLoader.projectRunnerBuildConfiguration(
            environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": "debug"]
        )
        let arguments = ConfigurationLoader.cachedRunnerBuildArguments(
            packageRoot: URL(fileURLWithPath: "/tmp/cache/abc"),
            buildConfiguration: configuration
        )
        let executable = ConfigurationLoader.cachedRunnerExecutableURL(
            in: URL(fileURLWithPath: "/tmp/cache/abc"),
            productName: "BumperProjectRunner",
            buildConfiguration: configuration
        )

        #expect(configuration == "debug")
        #expect(arguments.contains("debug"))
        #expect(!arguments.contains("release"))
        #expect(executable.path == "/tmp/cache/abc/.build/debug/BumperProjectRunner")
    }

    @Test(arguments: ["Release", "fast", "-O", "release debug", ""])
    func runnerBuildConfigurationRejectsUnsupportedValues(rawValue: String) throws {
        // Empty trims to the default; every other unsupported value must
        // fail loudly instead of silently selecting a configuration.
        if rawValue.isEmpty {
            #expect(try ConfigurationLoader.projectRunnerBuildConfiguration(
                environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": rawValue]
            ) == "release")
            return
        }

        #expect(throws: BumperError.self) {
            _ = try ConfigurationLoader.projectRunnerBuildConfiguration(
                environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": rawValue]
            )
        }
    }

    @Test
    func overriddenBuildConfigurationChangesCacheIdentity() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        try "let bumper = 1".write(to: configurationURL, atomically: true, encoding: .utf8)
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let release = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )
        let debug = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": "debug"]
        )

        #expect(release.root.path != debug.root.path)
        #expect(release.executableURL.path.hasSuffix(".build/release/BumperProjectRunner"))
        #expect(debug.executableURL.path.hasSuffix(".build/debug/BumperProjectRunner"))
    }

    @Test
    func cachedPackageIsReusedForUnchangedConfiguration() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        try "let bumper = 1".write(to: configurationURL, atomically: true, encoding: .utf8)
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let first = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )
        let second = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )

        #expect(first.root.path == second.root.path)
        #expect(first.executableURL.path == second.executableURL.path)
        #expect(second.executableURL.path.hasSuffix(".build/release/BumperProjectRunner"))
    }

    @Test(arguments: ["configuration", "source", "package", "library"])
    func ruleEditsKeepDependencyBuilds(edit: String) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        try "let bumper = 1".write(to: configurationURL, atomically: true, encoding: .utf8)
        let sourceURL = root.appendingPathComponent(".bumper/Sources/Rule.swift")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct Rule {}".write(to: sourceURL, atomically: true, encoding: .utf8)
        if edit == "package" {
            try "// package manifest".write(to: root.appendingPathComponent(".bumper/Package.swift"), atomically: true, encoding: .utf8)
        }
        let libraryRoot = root.appendingPathComponent("Library")
        let librarySource = libraryRoot.appendingPathComponent("Sources/Library.swift")
        try FileManager.default.createDirectory(at: librarySource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// manifest".write(to: libraryRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "struct Library {}".write(to: librarySource, atomically: true, encoding: .utf8)
        let environment = ["BUMPER_CACHE_DIR": root.appendingPathComponent("Cache").path]
        let first = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL, bumperPackageRoot: libraryRoot, environment: environment
        )
        let artifact = first.root.appendingPathComponent(".build/dependency-artifact")
        try FileManager.default.createDirectory(at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "preserved".write(to: artifact, atomically: true, encoding: .utf8)
        let editedURL = edit == "library" ? librarySource : (edit == "configuration" ? configurationURL : sourceURL)
        try "// edited rule".write(to: editedURL, atomically: true, encoding: .utf8)
        let second = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL, bumperPackageRoot: libraryRoot, environment: environment
        )
        #expect(first.root.standardizedFileURL.path == second.root.standardizedFileURL.path)
        #expect(try String(contentsOf: second.root.appendingPathComponent(".build/dependency-artifact"), encoding: .utf8) == "preserved")
        if edit == "source" {
            let copied = second.root.appendingPathComponent("Sources/BumperProjectRunner/ConsumerSources/Rule.swift")
            #expect(try String(contentsOf: copied, encoding: .utf8) == "// edited rule")
        }
    }

    @Test
    func cachedPackageRepairsCorruptedAndStaleInputs() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        let configuration = "let bumper = 1"
        try configuration.write(to: configurationURL, atomically: true, encoding: .utf8)

        let first = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: repositoryRoot(),
            environment: [:]
        )
        let manifestURL = first.root.appendingPathComponent("Package.swift")
        let expectedManifest = try Data(contentsOf: manifestURL)
        let sources = first.root.appendingPathComponent("Sources/BumperProjectRunner")
        let copiedConfiguration = sources.appendingPathComponent("UserConfiguration.swift")
        let staleSource = sources.appendingPathComponent("Stale.swift")
        try "corrupted".write(to: manifestURL, atomically: true, encoding: .utf8)
        try "corrupted".write(to: copiedConfiguration, atomically: true, encoding: .utf8)
        try "enum Stale {}".write(to: staleSource, atomically: true, encoding: .utf8)

        _ = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: repositoryRoot(),
            environment: [:]
        )

        #expect(try Data(contentsOf: manifestURL) == expectedManifest)
        #expect(try String(contentsOf: copiedConfiguration, encoding: .utf8) == configuration)
        #expect(!FileManager.default.fileExists(atPath: staleSource.path))
    }

    @Test
    func evaluationTimeoutDefaultsWhenUnset() throws {
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(environment: [:]) == 60)
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(
            environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": "  "]
        ) == 60)
    }

    @Test
    func evaluationTimeoutAcceptsValidOverrides() throws {
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(
            environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": "300"]
        ) == 300)
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(
            environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": "2.5"]
        ) == 2.5)
    }

    @Test(arguments: ["0", "-5", "abc", "nan", "inf", "-inf", "1e999", ""])
    func evaluationTimeoutRejectsInvalidOverrides(rawValue: String) {
        // Empty trims to the default; every other invalid form must fail
        // loudly instead of producing an unbounded or zero-length budget.
        if rawValue.isEmpty {
            #expect(throws: Never.self) {
                try ConfigurationLoader.configurationEvaluationTimeout(
                    environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": rawValue]
                )
            }
            return
        }

        #expect(throws: BumperError.self) {
            _ = try ConfigurationLoader.configurationEvaluationTimeout(
                environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": rawValue]
            )
        }
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
