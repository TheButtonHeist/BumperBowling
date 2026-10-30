import Foundation

public struct BumperProgressReporter: Sendable {
    private let handler: (@Sendable (String) -> Void)?

    public init(_ handler: (@Sendable (String) -> Void)? = nil) {
        self.handler = handler
    }

    public static let disabled = BumperProgressReporter()

    public func report(_ message: String) {
        handler?(message)
    }
}

public struct ScanReport: Equatable, Sendable, Codable {
    public let fileCount: Int
    public let coverage: SourceCoverageSummary?
    public let components: [String]
    public let dependencies: [ScanDependency]

    public init(repository: RepositoryFacts) {
        self.coverage = repository.coverage
        self.fileCount = repository.files.count
        self.components = Set(repository.files.compactMap { $0.component?.rawValue }).sorted()
        self.dependencies = repository.dependencyEdges
            .map(ScanDependency.init)
            .sorted { lhs, rhs in
                "\(lhs.sourceComponent).\(lhs.importedModule)" < "\(rhs.sourceComponent).\(rhs.importedModule)"
            }
    }

    public var markdownSummary: String {
        var lines: [String] = []
        lines.append("# Architecture Scan")
        lines.append("")
        lines.append("Files: \(fileCount)")
        lines.append("Components: \(components.joined(separator: ", "))")
        lines.append("")
        lines.append("## Dependencies")

        for dependency in dependencies {
            lines.append("- \(dependency.sourceComponent) imports \(dependency.importedModule)")
        }

        return lines.joined(separator: "\n")
    }
}

public struct ScanDependency: Equatable, Sendable, Codable {
    public let sourceComponent: String
    public let importedModule: String

    public init(sourceComponent: String, importedModule: String) {
        self.sourceComponent = sourceComponent
        self.importedModule = importedModule
    }

    public init(edge: DependencyEdge) {
        self.sourceComponent = edge.sourceComponent.rawValue
        self.importedModule = edge.importedModule.rawValue
    }
}

public struct LintRunResult: Sendable {
    public let rules: ArchitectureRules
    public let scannedFileCount: Int
    public let coverage: SourceCoverageSummary?
    public let report: RuleReport
    /// Per-rule and per-fact durations from the evaluation, for diagnosing
    /// slow project rules.
    public let telemetry: EvaluationTelemetry?
    /// Host-side phase durations for the whole run.
    public let phases: LintPhaseTimings?

    public init(
        rules: ArchitectureRules,
        scannedFileCount: Int,
        report: RuleReport,
        telemetry: EvaluationTelemetry? = nil,
        phases: LintPhaseTimings? = nil,
        coverage: SourceCoverageSummary? = nil
    ) {
        self.rules = rules
        self.coverage = coverage
        self.scannedFileCount = scannedFileCount
        self.report = report
        self.telemetry = telemetry
        self.phases = phases
    }

    func withPhases(_ phases: LintPhaseTimings) -> LintRunResult {
        LintRunResult(
            rules: rules,
            scannedFileCount: scannedFileCount,
            report: report,
            telemetry: telemetry,
            phases: phases,
            coverage: coverage
        )
    }

    public var enabledRuleCount: Int {
        BuiltInRules.rules(from: rules.ruleConfiguration).count
    }

    public func output(baseline: LintBaseline? = nil) -> LintOutput {
        LintOutput(
            report: report,
            rules: rules,
            coverage: coverage,
            baselineComparison: baseline.map { LintBaselineComparison(report: report, baseline: $0) }
        )
    }
}

/// Wall-clock seconds per lint phase, measured by the host around each
/// engine effect.
public struct LintPhaseTimings: Equatable, Sendable, Codable {
    public let prepareRulesSeconds: Double
    public let scanSeconds: Double
    public let evaluateSeconds: Double

    public init(
        prepareRulesSeconds: Double = 0,
        scanSeconds: Double = 0,
        evaluateSeconds: Double = 0
    ) {
        self.prepareRulesSeconds = prepareRulesSeconds
        self.scanSeconds = scanSeconds
        self.evaluateSeconds = evaluateSeconds
    }

    func recording(_ effect: LintRunEffect, seconds: Double) -> LintPhaseTimings {
        switch effect {
        case .prepareRules:
            return LintPhaseTimings(
                prepareRulesSeconds: prepareRulesSeconds + seconds,
                scanSeconds: scanSeconds,
                evaluateSeconds: evaluateSeconds
            )
        case .scanSources:
            return LintPhaseTimings(
                prepareRulesSeconds: prepareRulesSeconds,
                scanSeconds: scanSeconds + seconds,
                evaluateSeconds: evaluateSeconds
            )
        case .evaluateRules:
            return LintPhaseTimings(
                prepareRulesSeconds: prepareRulesSeconds,
                scanSeconds: scanSeconds,
                evaluateSeconds: evaluateSeconds + seconds
            )
        }
    }
}

public struct LintOutput: Equatable, Sendable, Codable {
    public let violations: [LintViolationOutput]
    public let summary: LintOutputSummary
    public let coverage: SourceCoverageSummary?

    public init(
        report: RuleReport,
        rules: ArchitectureRules,
        coverage: SourceCoverageSummary? = nil,
        baselineComparison: LintBaselineComparison? = nil
    ) {
        self.coverage = coverage
        let baselineIdentities = baselineComparison?.baseline.identities
        self.violations = report.violations.map { violation in
            LintViolationOutput(
                violation: violation,
                component: rules.component(containing: violation.path)?.id.rawValue,
                baselineState: baselineIdentities.map { $0.contains(LintBaselineIdentity(violation: violation)) ? .baseline : .new }
            )
        }
        self.summary = LintOutputSummary(
            totalViolations: report.violations.count,
            errorCount: report.violations.filter { $0.severity == .error }.count,
            warningCount: report.violations.filter { $0.severity == .warning }.count,
            noteCount: report.violations.filter { $0.severity == .note }.count,
            baseline: baselineComparison.map(LintBaselineOutputSummary.init)
        )
    }
}

public struct LintViolationOutput: Equatable, Sendable, Codable {
    public let ruleID: String
    public let severity: String
    public let component: String?
    public let path: String
    public let line: Int?
    public let column: Int?
    public let message: String
    public let observed: String?
    public let expected: String?
    public let baselineState: LintBaselineState?

    public init(
        violation: RuleViolation,
        component: String?,
        baselineState: LintBaselineState? = nil
    ) {
        self.ruleID = violation.ruleID.rawValue
        self.severity = violation.severity.rawValue
        self.component = component
        self.path = violation.path.rawValue
        self.line = violation.location?.line
        self.column = violation.location?.column
        self.message = violation.message
        self.observed = violation.evidence?.observed
        self.expected = violation.evidence?.expectation
        self.baselineState = baselineState
    }
}

public struct LintOutputSummary: Equatable, Sendable, Codable {
    public let totalViolations: Int
    public let errorCount: Int
    public let warningCount: Int
    public let noteCount: Int
    public let baseline: LintBaselineOutputSummary?
}

public struct LintBaselineOutputSummary: Equatable, Sendable, Codable {
    public let baselineViolationCount: Int
    public let existingViolationCount: Int
    public let newViolationCount: Int
    public let resolvedViolationCount: Int

    public init(comparison: LintBaselineComparison) {
        self.baselineViolationCount = comparison.baseline.violations.count
        self.existingViolationCount = comparison.existingViolations.count
        self.newViolationCount = comparison.newViolations.count
        self.resolvedViolationCount = comparison.resolvedViolations.count
    }
}

public enum LintBaselineState: String, Equatable, Sendable, Codable {
    case baseline
    case new
}

public struct LintBaseline: Equatable, Sendable, Codable {
    public let version: Int
    public let violations: [LintBaselineViolation]

    public init(version: Int = 1, violations: [LintBaselineViolation]) {
        self.version = version
        self.violations = violations
    }

    public init(report: RuleReport) {
        let entries = Set(report.violations.map(LintBaselineViolation.init))
        self.init(
            violations: entries.sorted { lhs, rhs in
                [
                    lhs.ruleID,
                    lhs.path,
                    lhs.message,
                    lhs.observed ?? "",
                    lhs.expected ?? ""
                ].joined(separator: "\u{0}") <
                    [
                        rhs.ruleID,
                        rhs.path,
                        rhs.message,
                        rhs.observed ?? "",
                        rhs.expected ?? ""
                    ].joined(separator: "\u{0}")
            }
        )
    }

    public func contains(_ violation: RuleViolation) -> Bool {
        identities.contains(LintBaselineIdentity(violation: violation))
    }

    fileprivate var identities: Set<LintBaselineIdentity> {
        Set(violations.map(LintBaselineIdentity.init))
    }
}

public struct LintBaselineViolation: Hashable, Sendable, Codable {
    public let ruleID: String
    public let severity: String
    public let path: String
    public let line: Int?
    public let column: Int?
    public let message: String
    public let observed: String?
    public let expected: String?

    public init(_ violation: RuleViolation) {
        self.ruleID = violation.ruleID.rawValue
        self.severity = violation.severity.rawValue
        self.path = violation.path.rawValue
        self.line = violation.location?.line
        self.column = violation.location?.column
        self.message = violation.message
        self.observed = violation.evidence?.observed
        self.expected = violation.evidence?.expectation
    }
}

public struct LintBaselineComparison: Equatable, Sendable {
    public let baseline: LintBaseline
    public let existingViolations: [RuleViolation]
    public let newViolations: [RuleViolation]
    public let resolvedViolations: [LintBaselineViolation]

    public init(report: RuleReport, baseline: LintBaseline) {
        let currentIdentities = Set(report.violations.map { LintBaselineIdentity(violation: $0) })
        let baselineIdentities = baseline.identities
        self.baseline = baseline
        self.existingViolations = report.violations.filter { baselineIdentities.contains(LintBaselineIdentity(violation: $0)) }
        self.newViolations = report.violations.filter { !baselineIdentities.contains(LintBaselineIdentity(violation: $0)) }
        self.resolvedViolations = baseline.violations.filter { entry in
            !currentIdentities.contains(LintBaselineIdentity(entry: entry))
        }
    }

    public var effectiveReport: RuleReport {
        RuleReport(violations: newViolations)
    }

    public var markdownSummary: String {
        var lines: [String] = []
        if newViolations.isEmpty {
            lines.append("No new architecture violations found.")
        } else {
            lines.append("New architecture violations found:")
            lines.append("")
            for violation in newViolations {
                let severity = violation.severity.rawValue.uppercased()
                lines.append(
                    "- [\(severity)] \(violation.markdownLocation): \(violation.message) " +
                        "(\(violation.ruleID.rawValue))"
                )
            }
        }
        lines.append("")
        let baselineSummary = [
            "\(existingViolations.count) existing",
            "\(newViolations.count) new",
            "\(resolvedViolations.count) resolved."
        ].joined(separator: ", ")
        lines.append(
            "Baseline: \(baselineSummary)"
        )
        return lines.joined(separator: "\n")
    }
}

private struct LintBaselineIdentity: Hashable {
    let ruleID: String
    let path: String
    let message: String
    let observed: String?
    let expected: String?

    init(violation: RuleViolation) {
        self.ruleID = violation.ruleID.rawValue
        self.path = violation.path.rawValue
        self.message = violation.message
        self.observed = violation.evidence?.observed
        self.expected = violation.evidence?.expectation
    }

    init(entry: LintBaselineViolation) {
        self.ruleID = entry.ruleID
        self.path = entry.path
        self.message = entry.message
        self.observed = entry.observed
        self.expected = entry.expected
    }
}

public enum LintFailureThreshold: String, Equatable, Sendable {
    case none
    case note
    case warning
    case error

    public func shouldFail(_ report: RuleReport) -> Bool {
        guard self != .none else {
            return false
        }
        return report.violations.contains { violation in
            violation.severity.rank >= severityRank
        }
    }

    private var severityRank: Int {
        switch self {
        case .none:
            Int.max
        case .note:
            Severity.note.rank
        case .warning:
            Severity.warning.rank
        case .error:
            Severity.error.rank
        }
    }
}

private extension Severity {
    var rank: Int {
        switch self {
        case .off:
            0
        case .note:
            1
        case .warning:
            2
        case .error:
            3
        }
    }
}
