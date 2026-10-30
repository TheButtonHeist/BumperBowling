import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Configuration Execution Safety", .serialized)
struct ConfigurationExecutionSafetyTests {
    /// Configurations are compiled and run to produce their value. That
    /// execution must not observe the caller's environment, must not be able
    /// to write files, and must still produce the value the config computes.
    @Test
    func executedConfigurationCannotReadEnvironmentOrWriteFiles() throws {
        setenv("BUMPER_CANARY_SECRET", "LEAKED", 1)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let leakURL = root.appendingPathComponent("leak.txt")

        let source = """
        import BumperBowlingCore
        import Foundation

        private func makeConfiguration() -> BumperProject {
            try? "leaked".write(toFile: \(leakURL.path.debugDescription), atomically: true, encoding: .utf8)
            let injected = ProcessInfo.processInfo.environment["BUMPER_CANARY_SECRET"] ?? "Sources"

            return BumperProject {
                Included {
                    injected
                }

                Architecture {
                    Component(.app) {
                        Owns("Sources")
                    }
                }
            }
        }

        let bumper = makeConfiguration()
        """
        try source.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try ConfigurationLoader.loadConfiguration(root: root)

        #expect(configuration.includedPaths == ["Sources"], "environment variables must not leak into evaluation")
        #expect(
            !FileManager.default.fileExists(atPath: leakURL.path),
            "sandboxed evaluation must not be able to write files"
        )
    }

    @Test
    func executedConfigurationCanUseConsumerOwnedShapeSources() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let consumerSourceRoot = root.appendingPathComponent(".bumper/Sources")
        try FileManager.default.createDirectory(at: consumerSourceRoot, withIntermediateDirectories: true)

        let houseStyle = """
        import BumperBowlingCore

        extension ComponentRequirement {
            static let domainHouseStyle = ComponentRequirement(
                .explicitDomainSurfaces,
                .immutableStoredState,
                .noOptionalStoredProperties
            )
        }

        let domainShape = ComponentShape {
            MayUse(.foundation)
            Requires(.domainHouseStyle, severity: .error)
        }
        """
        try houseStyle.write(
            to: consumerSourceRoot.appendingPathComponent("HouseStyle.swift"),
            atomically: true,
            encoding: .utf8
        )

        let configurationSource = """
        import BumperBowlingCore

        let bumper = BumperProject {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Modules("Core")
                    Applies(domainShape)
                }
            }
        }
        """
        try configurationSource.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let configurations = try await withThrowingTaskGroup(of: ArchitectureConfiguration.self) { group in
            for _ in 0..<8 {
                group.addTask { try ConfigurationLoader.loadConfiguration(root: root) }
            }
            var configurations: [ArchitectureConfiguration] = []
            for try await configuration in group { configurations.append(configuration) }
            return configurations
        }
        #expect(configurations.count == 8)
        #expect(configurations.allSatisfy { $0 == configurations.first })
        let configuration = try #require(configurations.first)
        let rules = configuration.rules

        #expect(configuration.components.map(\.name) == ["core"])
        #expect(rules.storedProperties.severity == .error)
        #expect(rules.storedProperties.paths == ["Sources/Core"])
        #expect(
            rules.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([.any, .broadExistential, .storedVar, .optionalState])
        )
    }

    @Test
    func executedConfigurationCanUseRenamedBumperPackageCheckout() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let renamedPackageRoot = temp.appendingPathComponent("BumperBowling-eval")
        let consumerRoot = temp.appendingPathComponent("Consumer")
        defer {
            try? FileManager.default.removeItem(at: temp)
        }

        try copyPackageSource(to: renamedPackageRoot)
        try FileManager.default.createDirectory(at: consumerRoot, withIntermediateDirectories: true)

        let configurationSource = """
        import BumperBowlingCore

        let bumper = BumperProject {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Modules("Core")
                    MayUse(.foundation)
                }
            }
        }
        """
        try configurationSource.write(
            to: consumerRoot.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let process = Process()
        process.executableURL = repositoryRoot().appendingPathComponent(".build/debug/bumper")
        process.arguments = ["config", consumerRoot.path]
        var environment = ProcessInfo.processInfo.environment
        environment["BUMPER_PACKAGE_PATH"] = renamedPackageRoot.path
        process.environment = environment

        let result = try ConfigurationLoader.runProcess(
            process,
            timeoutSeconds: 600,
            outputLimitBytes: 1024 * 1024
        )

        #expect(!result.timedOut)
        #expect(result.terminationStatus == 0, "\(String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>")")
    }

    /// The override must reach the runner's process budget, and the budget
    /// must still terminate a stuck evaluator instead of waiting forever.
    @Test
    func evaluationTimeoutOverrideBoundsStuckEvaluator() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let originalTimeout = ProcessInfo.processInfo.environment["BUMPER_EVALUATION_TIMEOUT_SECONDS"]
        defer {
            restoreEnvironmentValue(named: "BUMPER_EVALUATION_TIMEOUT_SECONDS", to: originalTimeout)
            try? FileManager.default.removeItem(at: root)
        }

        let source = """
        import BumperBowlingCore
        import Foundation

        let bumper = BumperProject {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                }
            }

            Rules {
                Rules.repository(
                    "stuck.rule",
                    summary: "Blocks indefinitely to verify evaluator timeout enforcement."
                ) { _ in
                    Thread.sleep(forTimeInterval: 300)
                    return []
                }
            }
        }
        """
        try source.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try ConfigurationLoader.loadConfiguration(root: root)
        setenv("BUMPER_EVALUATION_TIMEOUT_SECONDS", "2", 1)

        do {
            _ = try ConfigurationLoader.evaluateRun(
                root: root,
                input: RepositoryInput(architecture: configuration, files: [])
            )
            Issue.record("a stuck evaluator must be terminated by the configured budget")
        } catch let error as BumperError {
            guard case .configurationExecutionTimedOut(_, let seconds) = error else {
                throw error
            }
            #expect(seconds == 2)
        }
    }

    @Test
    func configurationRunnerCacheDirectoryCanBeCustomized() {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let cacheRoot = temp.appendingPathComponent("BumperCache")
        let resolvedRoot = ConfigurationLoader.configurationCacheRoot(
            environment: ["BUMPER_CACHE_DIR": cacheRoot.path]
        )

        #expect(resolvedRoot == cacheRoot.standardizedFileURL)
    }

    @Test
    func executedConfigurationCanImportLocalRulePackage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let packageRoot = root.appendingPathComponent(".bumper")
        let packageSources = packageRoot.appendingPathComponent("Sources/BumperRules")
        try FileManager.default.createDirectory(at: packageSources, withIntermediateDirectories: true)

        let packageManifest = """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "BumperRules",
            platforms: [.macOS(.v15)],
            products: [
                .library(name: "BumperRules", targets: ["BumperRules"])
            ],
            dependencies: [
                .package(name: "BumperBowling", path: \(repositoryRoot().path.debugDescription))
            ],
            targets: [
                .target(
                    name: "BumperRules",
                    dependencies: [
                        .product(name: "BumperBowlingCore", package: "BumperBowling")
                    ],
                    resources: [.copy("ScanPath.txt")]
                )
            ]
        )
        """
        try packageManifest.write(
            to: packageRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let resource = packageSources.appendingPathComponent("ScanPath.txt")
        try "Sources".write(to: resource, atomically: true, encoding: .utf8)
        let rules = """
        import BumperBowlingCore
        import Foundation

        public var scanPath: String {
            try! String(contentsOf: Bundle.module.url(forResource: "ScanPath", withExtension: "txt")!, encoding: .utf8)
        }

        public extension ComponentShape {
            static let importedDomain = ComponentShape {
                MayUse(.foundation)
                Requires(.noBoolStoredProperties, severity: .warning)
            }
        }
        """
        try rules.write(to: packageSources.appendingPathComponent("Rules.swift"), atomically: true, encoding: .utf8)

        let configurationSource = """
        import BumperBowlingCore
        import BumperRules

        let bumper = BumperProject {
            Included { scanPath }
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Applies(.importedDomain)
                }
            }
        }
        """
        try configurationSource.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try ConfigurationLoader.loadConfiguration(root: root)

        #expect(configuration.rules.storedProperties.severity == .warning)
        #expect(configuration.rules.storedProperties.disallowances == [.boolState])
        #expect(configuration.includedPaths == ["Sources"])
        try "Tests".write(to: resource, atomically: true, encoding: .utf8)
        let updated = try ConfigurationLoader.loadConfiguration(root: root)
        #expect(updated.includedPaths == ["Tests"])
    }
}

private func restoreEnvironmentValue(named name: String, to value: String?) {
    if let value {
        setenv(name, value, 1)
    } else {
        unsetenv(name)
    }
}

private func copyPackageSource(to destination: URL) throws {
    let source = repositoryRoot()
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for child in ["Package.swift", "Sources"] {
        try FileManager.default.copyItem(
            at: source.appendingPathComponent(child),
            to: destination.appendingPathComponent(child)
        )
    }
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
