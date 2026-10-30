import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Source coverage")
struct SourceCoverageTests {
    @Test
    func rawScanIncludesUnownedSources() async throws {
        let root = try makeRepository(["Sources/New/Probe.swift": "import Foundation\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = try RepositoryScanner(configuration: ArchitectureConfiguration(
            components: [ComponentConfiguration(name: "core", paths: ["Sources/Core"])]
        ))

        let files = try await scanner.scanSources(root: root)
        #expect(files.map(\.path.rawValue) == ["Sources/New/Probe.swift"])
        #expect(files.first?.source == "import Foundation\n")
        #expect(files.first?.component == nil)
        let file = try await scanner.scanFile(root.appendingPathComponent("Sources/New/Probe.swift"), root: root)
        #expect(file.component == nil)
        #expect(file.imports.map(\.rawValue) == ["Foundation"])
    }

    @Test
    func lintRetainsCoverageAcrossRunnerInputAndStructuredOutput() async throws {
        let root = try makeRepository([
            "Sources/New/Z.swift": "import UIKit\n",
            "Sources/New/A.swift": "let value: Any = 0\n",
            "Sources/Excluded/Ignored.swift": "struct Ignored {}\n",
            "Outside/Ignored.swift": "struct Outside {}\n",
            "Sources/Core/Shared/Owned.swift": "struct Owned {}\n",
            "Sources/Shim/Bridge.m": "@implementation Bridge\n@end\n",
            "Sources/Shim/Bridge.h": "@interface Bridge\n@end\n",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = ArchitectureConfiguration(
            excludedPaths: ["Sources/Excluded"],
            components: [
                ComponentConfiguration(name: "core", paths: ["Sources/Core"]),
                ComponentConfiguration(name: "shared", paths: ["Sources/Core/Shared"]),
                ComponentConfiguration(name: "shim", paths: ["Sources/Shim"]),
                ComponentConfiguration(name: "missing", paths: ["Sources/Typo"]),
            ],
            rules: [SingleOwner(.error), SourceCoverage(.error)].combined()
        )
        let scanner = try RepositoryScanner(configuration: configuration)
        let input = try await scanner.scanInput(root: root)
        // The runner receives JSON, so exercise that boundary before evaluation.
        let decoded = try JSONDecoder().decode(RepositoryInput.self, from: JSONEncoder().encode(input))
        #expect(decoded.files.count == 3)
        #expect(decoded.files.filter { $0.component == nil }.map(\.path.rawValue) == ["Sources/New/A.swift", "Sources/New/Z.swift"])
        let report = try BumperProject {}.evaluate(decoded)
        let result = try await BumperCommands.lintRun(root: root, configuration: configuration)
        #expect(result.report == report)
        let coverage = try #require(result.coverage)
        #expect(coverage.includedFileCount == 5)
        #expect(coverage.scannedFileCount == 3)
        #expect(coverage.unownedFileCount == 2)
        #expect(coverage.unownedPaths.map(\.rawValue) == ["Sources/New/A.swift", "Sources/New/Z.swift"])
        #expect(coverage.overlappingPaths.map(\.rawValue) == ["Sources/Core/Shared/Owned.swift"])
        #expect(coverage.languages.map(\.fileExtension) == ["h", "m", "swift"])
        #expect(coverage.languages.filter(\.isSupported).map(\.scannedFileCount) == [3])
        let findings = report.violations.filter { $0.ruleID == .sourceCoverage }
        #expect(findings.count == 5)
        #expect(findings.filter { $0.severity == .error }.map(\.path.rawValue) == [
            "Sources/Core/Shared/Owned.swift", "Sources/New/A.swift", "Sources/New/Z.swift",
        ])
        #expect(findings.filter { $0.severity == .warning }.map(\.path.rawValue) == ["Sources/Typo"])
        #expect(findings.filter { $0.severity == .note }.map(\.path.rawValue) == ["Sources/Shim"])
        #expect(report.violations.contains { $0.ruleID == .duplicateOwnership })
        let output = result.output()
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(output)) as? [String: Any])
        let jsonCoverage = try #require(json["coverage"] as? [String: Any])
        #expect(jsonCoverage["unownedFileCount"] as? Int == 2)
        let unownedOutput = try #require(output.violations.first { $0.path == "Sources/New/A.swift" })
        #expect(unownedOutput.component == nil)
        let scan = try await BumperCommands.scanReport(root: root, configuration: configuration)
        #expect(scan.coverage == coverage)
        #expect(scan.fileCount == 3)
    }

    @Test func syntaxOnlyProjectScansAndEvaluatesWithoutComponents() async throws {
        let root = try makeRepository(["Sources/Model.swift": "struct Model {}"])
        defer { try? FileManager.default.removeItem(at: root) }
        let project = BumperProject {
            Rules {
                Rules.forbid(structs().filter { $0.node.name.text == "Forbidden" }, id: "project.forbidden") { _ in
                    "Forbidden declaration."
                }
            }
        }
        let scanner = try RepositoryScanner(scan: project.scanConfiguration)
        let passing = try project.evaluate(try await scanner.scanInput(root: root))
        #expect(passing.violations.isEmpty)
        try "struct Forbidden {}".write(to: root.appendingPathComponent("Sources/Model.swift"), atomically: true, encoding: .utf8)
        let input = try await scanner.scanInput(root: root)
        let decoded = try JSONDecoder().decode(RepositoryInput.self, from: JSONEncoder().encode(input))
        let failing = try project.evaluate(decoded)
        #expect(failing.violations.count == 1)
        let violation = try #require(failing.violations.first)
        #expect(violation.ruleID == RuleID("project.forbidden"))
        #expect(violation.path.rawValue == "Sources/Model.swift")
        #expect(violation.location == SourcePosition(line: 1, column: 1))
        #expect(violation.message == "Forbidden declaration.")
        let facts = try await scanner.scan(root: root)
        let graph = ArchitectureGraph(nodes: facts, rules: try ArchitectureRules(configuration: ArchitectureConfiguration()))
        #expect(facts.files.count == 1)
        #expect(graph.componentNodes.isEmpty)
        #expect(graph.moduleImportEdges.isEmpty)
        #expect(graph.componentImportEdges.isEmpty)
    }

    @Test(arguments: [false, true])
    func unsupportedSymlinksAreInventoriedWithoutReadingTargets(coverageEnabled: Bool) async throws {
        let root = try makeRepository([
            "Sources/Core/Core.swift": "struct Core {}",
            "Sources/Core/Original.h": "void bridge(void);",
        ])
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data([0xFF]).write(to: outside)
        let directory = root.appendingPathComponent("Sources/Core")
        for (name, target) in [
            ("Public.h", directory.appendingPathComponent("Original.h")),
            ("External.h", outside),
            ("Dangling.h", outside.appendingPathExtension("missing")),
        ] {
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(name), withDestinationURL: target)
        }
        let result = try await BumperCommands.lintRun(root: root, configuration: ArchitectureConfiguration(
            components: [ComponentConfiguration(name: "core", paths: ["Sources/Core"])],
            rules: coverageEnabled ? SourceCoverage(.error) : RuleConfiguration()
        ))
        #expect(result.report.violations.isEmpty)
        let coverage = try #require(result.coverage)
        #expect(coverage.includedFileCount == 5)
        #expect(coverage.scannedFileCount == 1)
        let headers = try #require(coverage.languages.first { $0.fileExtension == "h" })
        #expect(headers.includedFileCount == 4)
        #expect(headers.scannedFileCount == 0)
    }

    @Test
    func coverageRequiresAnInventoryRatherThanReportingFalseSuccess() throws {
        let configuration = ArchitectureConfiguration(components: [], rules: SourceCoverage(.error))
        #expect(throws: RuleEvaluationError.self) {
            try BumperProject {}.evaluate(RepositoryInput(architecture: configuration, files: []))
        }
        // Older wire inputs without the optional coverage fields still decode.
        let data = try JSONEncoder().encode(RepositoryInput(architecture: ArchitectureConfiguration(components: []), files: []))
        let decoded = try JSONDecoder().decode(RepositoryInput.self, from: data)
        #expect(decoded.coverage == nil)
        #expect(decoded.architecture.rules.sourceCoverage == nil)
    }

    private func makeRepository(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (path, source) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }
}
