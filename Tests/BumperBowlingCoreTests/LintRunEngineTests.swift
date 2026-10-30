import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Lint run engine")
struct LintRunEngineTests {
    @Test
    func `reducer starts by preparing rules`() {
        let configuration = ArchitectureConfiguration(components: [])
        let transition = LintRunReducer().reduce(
            state: .idle,
            event: .start(configuration)
        )

        expectPreparingRules(transition.state, configuration)
        #expect(transition.effect == .prepareRules(configuration))
    }

    @Test
    func `reducer scans after rules are prepared`() throws {
        let configuration = ArchitectureConfiguration(components: [])
        let preparedRules = LintPreparedRules(
            configuration: configuration,
            rules: try ArchitectureRules(configuration: configuration)
        )

        let transition = LintRunReducer().reduce(
            state: .preparingRules(configuration),
            event: .preparedRules(preparedRules)
        )

        expectScanningSources(transition.state, preparedRules)
        #expect(transition.effect == .scanSources(preparedRules))
    }

    @Test
    func `reducer evaluates rules after scanning sources`() throws {
        let configuration = ArchitectureConfiguration(components: [])
        let rules = try ArchitectureRules(configuration: configuration)
        let preparedRules = LintPreparedRules(configuration: configuration, rules: rules)
        let files = [SourceInput(path: RelativeFilePath("Sources/Core/Thing.swift"), component: try ComponentID("core"), source: "struct Thing {}")]
        let plan = LintEvaluationPlan(configuration: configuration, rules: rules, files: files, coverage: nil)

        let transition = LintRunReducer().reduce(
            state: .scanningSources(preparedRules),
            event: .scannedSources(preparedRules: preparedRules, files: files)
        )

        expectEvaluatingRules(transition.state, plan)
        #expect(transition.effect == .evaluateRules(plan))
    }

    @Test
    func `reducer reports after evaluating rules`() throws {
        let configuration = ArchitectureConfiguration(components: [])
        let rules = try ArchitectureRules(configuration: configuration)
        let files = [SourceInput(path: RelativeFilePath("Sources/Core/Thing.swift"), component: try ComponentID("core"), source: "struct Thing {}")]
        let plan = LintEvaluationPlan(configuration: configuration, rules: rules, files: files, coverage: nil)
        let run = EvaluationRun(
            report: RuleReport(violations: []),
            telemetry: EvaluationTelemetry(ruleSeconds: [], factSeconds: [], totalSeconds: 0.5)
        )
        let transition = LintRunReducer().reduce(
            state: .evaluatingRules(plan),
            event: .evaluatedRules(plan: plan, run: run)
        )

        expectReporting(transition.state, rules: rules, scannedFileCount: files.count, report: run.report)
        guard case .reporting(let result) = transition.state else {
            return
        }
        #expect(result.telemetry == run.telemetry)
        #expect(transition.effect == nil)
    }

    @Test
    func `engine run carries telemetry and phase timings`() async throws {
        // No BumperBowling.swift in the root: built-in rules evaluate in
        // process, so the run exercises the telemetry path without the runner.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/Core"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct Thing {}".write(
            to: root.appendingPathComponent("Sources/Core/Thing.swift"),
            atomically: true,
            encoding: .utf8
        )
        let configuration = ArchitectureConfiguration(
            components: [ComponentConfiguration(name: "Core", paths: ["Sources/Core"])]
        )

        let result = try await LintRunEngine(root: root, configuration: configuration).run()

        let telemetry = try #require(result.telemetry)
        #expect(telemetry.totalSeconds >= 0)
        let phases = try #require(result.phases)
        #expect(phases.evaluateSeconds >= 0)
        #expect(phases.scanSeconds >= 0)
    }
}

private func expectPreparingRules(
    _ state: LintRunState,
    _ configuration: ArchitectureConfiguration
) {
    guard case .preparingRules(let actualConfiguration) = state else {
        Issue.record("Expected preparingRules state")
        return
    }
    #expect(actualConfiguration == configuration)
}

private func expectScanningSources(
    _ state: LintRunState,
    _ preparedRules: LintPreparedRules
) {
    guard case .scanningSources(let actualPreparedRules) = state else {
        Issue.record("Expected scanningSources state")
        return
    }
    #expect(actualPreparedRules == preparedRules)
}

private func expectEvaluatingRules(
    _ state: LintRunState,
    _ plan: LintEvaluationPlan
) {
    guard case .evaluatingRules(let actualPlan) = state else {
        Issue.record("Expected evaluatingRules state")
        return
    }
    #expect(actualPlan == plan)
}

private func expectReporting(
    _ state: LintRunState,
    rules: ArchitectureRules,
    scannedFileCount: Int,
    report: RuleReport
) {
    guard case .reporting(let result) = state else {
        Issue.record("Expected reporting state")
        return
    }
    #expect(result.rules == rules)
    #expect(result.scannedFileCount == scannedFileCount)
    #expect(result.report == report)
}
