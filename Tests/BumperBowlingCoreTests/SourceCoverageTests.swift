import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Source coverage")
struct SourceCoverageTests {
    @Test
    func rawScanRejectsUnownedSourcesInsteadOfReturningEmptyInput() async throws {
        let root = try makeRepository(["Sources/New/Probe.swift": "import Foundation\n"])
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = try RepositoryScanner(configuration: ArchitectureConfiguration(
            components: [ComponentConfiguration(name: "core", paths: ["Sources/Core"])]
        ))

        do {
            _ = try await scanner.scanSources(root: root)
            Issue.record("Expected an unowned source to fail the raw scan.")
        } catch let error as BumperError {
            guard case .noComponentForFile(let path) = error else { throw error }
            #expect(path == "Sources/New/Probe.swift")
        }
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
        let report = try BumperProject {}.evaluate(decoded)
        let result = try await BumperCommands.lintRun(root: root, configuration: configuration)
        #expect(result.report == report)
        let coverage = try #require(result.coverage)
        #expect(coverage.includedFileCount == 5)
        #expect(coverage.scannedFileCount == 1)
        #expect(coverage.unownedFileCount == 2)
        #expect(coverage.unownedPaths.map(\.rawValue) == ["Sources/New/A.swift", "Sources/New/Z.swift"])
        #expect(coverage.overlappingPaths.map(\.rawValue) == ["Sources/Core/Shared/Owned.swift"])
        #expect(coverage.languages.map(\.fileExtension) == ["h", "m", "swift"])
        #expect(coverage.languages.filter(\.isSupported).map(\.scannedFileCount) == [1])
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
        #expect(scan.fileCount == 1)
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
