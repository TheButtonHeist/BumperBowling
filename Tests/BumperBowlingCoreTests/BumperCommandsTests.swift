import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("BumperCommands")
struct BumperCommandsTests {
    @Test
    func scanSummarizesConfiguredRepository() async throws {
        let root = try makeRepository(source: """
        import Foundation

        public struct Thing {}
        """)

        let output = try await BumperCommands.scan(
            root: root,
            configuration: commandFixtureConfiguration
        )

        #expect(output.contains("Files: 1"))
        #expect(output.contains("Components: core"))
        #expect(output.contains("core imports Foundation"))
    }

    @Test
    func scanReportCarriesStructuredRepositoryFacts() async throws {
        let root = try makeRepository(source: """
        import Foundation

        public struct Thing {}
        """)

        let report = try await BumperCommands.scanReport(
            root: root,
            configuration: commandFixtureConfiguration
        )

        #expect(report.fileCount == 1)
        #expect(report.components == ["core"])
        #expect(report.dependencies == [ScanDependency(sourceComponent: "core", importedModule: "Foundation")])
    }

    @Test
    func lintReportsErrorsForFailingFixture() async throws {
        let root = try makeRepository(source: """
        import XCTest

        public struct Thing {}
        """)

        let report = try await BumperCommands.lint(
            root: root,
            configuration: commandFixtureConfiguration
        )

        #expect(report.hasErrors)
        #expect(report.violations.map(\.ruleID).contains(.forbiddenImport))
    }

    @Test
    func lintOutputCarriesCIFieldsAndComponents() async throws {
        let root = try makeRepository(source: """
        import XCTest

        public struct Thing {}
        """)

        let run = try await BumperCommands.lintRun(
            root: root,
            configuration: commandFixtureConfiguration
        )
        let output = run.output()
        let forbiddenImport = try #require(output.violations.first { violation in
            violation.ruleID == RuleID.forbiddenImport.rawValue
        })

        #expect(output.summary.totalViolations == output.violations.count)
        #expect(output.summary.errorCount == output.violations.filter { $0.severity == Severity.error.rawValue }.count)
        #expect(forbiddenImport.severity == Severity.error.rawValue)
        #expect(forbiddenImport.component == "core")
        #expect(forbiddenImport.path == "Sources/BumperBowlingCore/Thing.swift")
    }

    @Test
    func baselineComparisonSuppressesExistingViolationsOnly() async throws {
        let root = try makeRepository(source: """
        import XCTest
        import Foundation

        public struct Thing {}
        """)
        var configuration = commandFixtureConfiguration
        configuration = ArchitectureConfiguration(
            includedPaths: configuration.includedPaths,
            excludedPaths: configuration.excludedPaths,
            components: configuration.components,
            rules: RuleConfiguration(
                forbiddenImports: [
                    RuleSetting(severity: .error, values: ["XCTest"]),
                    RuleSetting(severity: .error, values: ["Foundation"])
                ],
                duplicateOwnership: .error
            )
        )

        let run = try await BumperCommands.lintRun(root: root, configuration: configuration)
        let xctestOnlyBaseline = LintBaseline(
            violations: run.report.violations
                .filter { $0.message.contains("XCTest") }
                .map(LintBaselineViolation.init)
        )
        let comparison = LintBaselineComparison(report: run.report, baseline: xctestOnlyBaseline)

        #expect(comparison.existingViolations.count == 1)
        #expect(comparison.newViolations.count == 1)
        #expect(comparison.effectiveReport.violations.first?.message.contains("Foundation") == true)
        #expect(run.output(baseline: xctestOnlyBaseline).summary.baseline?.newViolationCount == 1)
    }

    @Test
    func failureThresholdControlsExitIntent() throws {
        let report = RuleReport(
            violations: [
                RuleViolation(
                    rule: RuleMetadata(id: .forbiddenImport, severity: .warning, summary: "Forbidden import."),
                    path: RelativeFilePath("Sources/Core/Thing.swift"),
                    message: "warning"
                )
            ]
        )

        #expect(!LintFailureThreshold.none.shouldFail(report))
        #expect(!LintFailureThreshold.error.shouldFail(report))
        #expect(LintFailureThreshold.warning.shouldFail(report))
        #expect(LintFailureThreshold.note.shouldFail(report))
    }

    @Test
    func lintLoadsBumperBowlingSwiftConfiguration() async throws {
        let root = try makeRepository(source: """
        import Foundation

        public struct Thing {}
        """)
        try writeConfiguration(to: root)

        let report = try await BumperCommands.lint(root: root)

        #expect(!report.hasErrors)
    }

    @Test
    func changedBumperBowlingSwiftInvalidatesConfigurationRunnerCache() async throws {
        let root = try makeRepository(source: """
        import Foundation

        public struct Thing {}
        """)
        try writeConfiguration(to: root, forbiddenModule: "XCTest")

        let cleanReport = try await BumperCommands.lint(root: root)
        #expect(!cleanReport.hasErrors)

        try writeConfiguration(to: root, forbiddenModule: "Foundation")

        let failingReport = try await BumperCommands.lint(root: root)
        #expect(failingReport.hasErrors)
        #expect(failingReport.violations.contains { violation in
            violation.message.contains("Foundation")
        })
    }

    @Test
    func lintRunsCustomRulesWithoutArchitecture() async throws {
        let root = try makeRepository(source: """
        import Foundation
        import UIKit

        public struct Thing {}
        """)
        try writeCustomRuleConfiguration(to: root)
        try writeCustomRuleSource(to: root)

        let report = try await BumperCommands.lint(root: root)
        let violation = try #require(report.violations.first { violation in
            violation.ruleID == RuleID("custom.import_allow_list")
        })

        #expect(report.hasErrors)
        #expect(violation.path.rawValue == "Sources/BumperBowlingCore/Thing.swift")
        #expect(violation.message.contains("UIKit"))
        #expect(violation.evidence?.expectation == "allowed imports: Foundation")
        try "import Foundation\npublic struct Thing {}".write(
            to: root.appendingPathComponent("Sources/BumperBowlingCore/Thing.swift"), atomically: true, encoding: .utf8
        )
        let passing = try await BumperCommands.lint(root: root)
        #expect(passing.violations.isEmpty)
    }

    @Test
    func lintRunsCustomSyntaxRulesWithoutArchitecture() async throws {
        let root = try makeRepository(source: """
        public struct Thing {
            public func pair() -> (String, Int) {
                ("id", 1)
            }
        }
        """)
        try writeCustomRuleConfiguration(to: root)
        try writeCustomSyntaxRuleSource(to: root)

        let report = try await BumperCommands.lint(root: root)
        let violation = try #require(report.violations.first { violation in
            violation.ruleID == RuleID("custom.no_tuple_types")
        })

        #expect(report.hasErrors)
        #expect(violation.path.rawValue == "Sources/BumperBowlingCore/Thing.swift")
        #expect(violation.message == "Tuple types must use named values.")
        #expect(violation.evidence?.observed == "(String, Int)")
    }

    @Test
    func initWritesRunnableConfiguration() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)

        try BumperCommands.initialize(at: root)

        let report = try await BumperCommands.lint(root: root)

        #expect(!report.hasErrors)
    }

    @Test
    func architectureSnapshotIsDeterministicCommandOutput() throws {
        let root = repositoryRoot()
        let checkedInSnapshot = try String(
            contentsOf: root.appendingPathComponent("docs/ARCHITECTURE_SNAPSHOT.md"),
            encoding: .utf8
        )

        #expect(
            checkedInSnapshot == (try BumperCommands.snapshot(root: root))
        )
    }

    private var commandFixtureConfiguration: ArchitectureConfiguration {
        BumperProject {
            Included {
                "Sources"
            }

            Architecture {
                Component(.core) {
                    Owns("Sources/BumperBowlingCore")
                    Modules("BumperBowlingCore")
                    MayUse(.foundation)
                    DoesNotUse(.testing)
                }
            }

            Rules {
                SingleOwner(.error)
            }
        }.architecture
    }

    private func makeRepository(source: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let sourceFile = root.appendingPathComponent("Sources/BumperBowlingCore/Thing.swift")
        try FileManager.default.createDirectory(
            at: sourceFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)
        return root
    }

    private func writeConfiguration(to root: URL, forbiddenModule: String = "XCTest") throws {
        // The helper function keeps this configuration outside the
        // declarative subset so these tests cover the sandboxed runner and
        // its cache instead of the static interpreter.
        let configuration = """
        import BumperBowlingCore

        private func makeConfiguration() -> BumperProject {
            BumperProject {
            Included {
                "Sources"
            }

            Excluded {
                ".build"
                "DerivedData"
            }

            Architecture {
                Component(.core) {
                    Owns("Sources/BumperBowlingCore")
                    Modules("BumperBowlingCore")
                    MayUse(.foundation)
                    DoesNotUse("\(forbiddenModule)", severity: .error)
                }
            }

            Rules {
                SingleOwner(.error)
            }
            }
        }

        let bumper = makeConfiguration()
        """

        try configuration.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeCustomRuleConfiguration(to root: URL) throws {
        let configuration = """
        import BumperBowlingCore

        let bumper = BumperProject {
            Included {
                "Sources"
            }

            Rules {
                projectRules
            }
        }
        """

        try configuration.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeCustomRuleSource(to root: URL) throws {
        let source = """
        import BumperBowlingCore

        let projectRules = RuleSet {
            Rules.repository(
                "custom.import_allow_list",
                severity: .error,
                summary: "Only Foundation imports are allowed."
            ) { context in
                let allowedImports = Set(["Foundation"])
                return try context.facts(BuiltInFacts.imports).occurrences
                    .filter { !allowedImports.contains($0.module.rawValue) }
                    .map { occurrence in
                        RuleFailure(
                            path: occurrence.path,
                            message: "\\(occurrence.component?.rawValue ?? "Unowned source") imports non-allowlisted module \\(occurrence.module.rawValue)",
                            evidence: ViolationEvidence(
                                observed: occurrence.module.rawValue,
                                expectation: "allowed imports: Foundation"
                            )
                        )
                    }
            }
        }
        """

        let sourceURL = root.appendingPathComponent(".bumper/Sources/CustomRules.swift")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    }

    private func writeCustomSyntaxRuleSource(to root: URL) throws {
        let source = """
        import BumperBowlingCore
        import SwiftSyntax

        let projectRules = RuleSet {
            Rules.files(
                "custom.no_tuple_types",
                severity: .error,
                summary: "Tuple types must be replaced by named types."
            ) { file in
                let visitor = TupleTypeCollector(viewMode: .sourceAccurate)
                visitor.walk(file.syntax)

                return visitor.tuples.map { tuple in
                    file.failure(
                        at: tuple,
                        message: "Tuple types must use named values.",
                        evidence: ViolationEvidence(
                            observed: tuple.trimmedDescription,
                            expectation: "named type"
                        )
                    )
                }
            }
        }

        private final class TupleTypeCollector: SyntaxVisitor {
            private(set) var tuples: [TupleTypeSyntax] = []

            override func visit(_ node: TupleTypeSyntax) -> SyntaxVisitorContinueKind {
                tuples.append(node)
                return .skipChildren
            }
        }
        """

        let sourceURL = root.appendingPathComponent(".bumper/Sources/CustomRules.swift")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
