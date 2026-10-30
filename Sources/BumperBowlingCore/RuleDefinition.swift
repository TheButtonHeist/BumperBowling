import Foundation

/// Identity, severity, and invariant summary for one rule.
/// `summary` describes the invariant; it is not the violation message.
public struct RuleMetadata: Equatable, Sendable, Codable {
    public let id: RuleID
    public let severity: Severity
    public let summary: String

    public init(id: RuleID, severity: Severity, summary: String) {
        self.id = id
        self.severity = severity
        self.summary = summary
    }
}

/// One diagnostic produced by rule evaluation, before rule metadata attaches.
public struct RuleFailure: Equatable, Sendable {
    public let path: RelativeFilePath
    public let location: SourcePosition?
    public let message: String
    public let evidence: ViolationEvidence?
    /// Overrides the rule's severity for this one diagnostic. Rules with
    /// per-scope configured severities report each finding at its scope's
    /// severity while keeping one stable rule ID.
    public let severity: Severity?

    public init(
        path: RelativeFilePath,
        location: SourcePosition? = nil,
        message: String,
        evidence: ViolationEvidence? = nil,
        severity: Severity? = nil
    ) {
        self.path = path
        self.location = location
        self.message = message
        self.evidence = evidence
        self.severity = severity
    }
}

/// The canonical structured diagnostic. Evaluation, tests, CLI, JSON, and
/// Markdown all project this one value.
public struct RuleViolation: Equatable, Sendable, Codable {
    public let rule: RuleMetadata
    public let path: RelativeFilePath
    public let location: SourcePosition?
    public let message: String
    public let evidence: ViolationEvidence?

    public init(
        rule: RuleMetadata,
        path: RelativeFilePath,
        location: SourcePosition? = nil,
        message: String,
        evidence: ViolationEvidence? = nil
    ) {
        self.rule = rule
        self.path = path
        self.location = location
        self.message = message
        self.evidence = evidence
    }

    public init(rule: RuleMetadata, failure: RuleFailure) {
        self.init(
            rule: failure.severity.map { severity in
                RuleMetadata(id: rule.id, severity: severity, summary: rule.summary)
            } ?? rule,
            path: failure.path,
            location: failure.location,
            message: failure.message,
            evidence: failure.evidence
        )
    }

    public var ruleID: RuleID {
        rule.id
    }

    public var severity: Severity {
        rule.severity
    }

    public var markdownLocation: String {
        guard let location else {
            return path.rawValue
        }

        return "\(path.rawValue):\(location.line):\(location.column)"
    }
}

/// The canonical structured report over one evaluation.
public struct RuleReport: Equatable, Sendable, Codable {
    public let violations: [RuleViolation]

    public init(violations: [RuleViolation]) {
        self.violations = violations
    }

    public var hasErrors: Bool {
        violations.contains { violation in
            violation.rule.severity == .error
        }
    }

    public var markdownSummary: String {
        if violations.isEmpty {
            return "No architecture violations found."
        }

        var lines = [
            hasErrors ? "The code breaks the architecture's rules:" : "The architecture holds, but note these warnings:",
            "",
        ]
        for violation in violations {
            lines.append(
                "- [\(violation.severity.rawValue.uppercased())] \(violation.markdownLocation): \(violation.message) (\(violation.ruleID.rawValue))"
            )
        }
        return lines.joined(separator: "\n")
    }
}

/// One rule: identity, scope, and evaluation over an immutable context.
/// Built-in and consumer rules conform to this same protocol.
public protocol RuleDefinition: Sendable {
    var metadata: RuleMetadata { get }
    var scope: RuleScope { get }

    func evaluate(in context: RuleContext) throws -> [RuleFailure]
}

@resultBuilder
public enum RuleSetBuilder {
    public static func buildExpression(_ expression: some RuleDefinition) -> [any RuleDefinition] {
        [expression]
    }

    public static func buildExpression(_ expression: [any RuleDefinition]) -> [any RuleDefinition] {
        expression
    }

    public static func buildExpression(_ expression: RuleSet) -> [any RuleDefinition] {
        expression.rules
    }

    public static func buildBlock(_ components: [any RuleDefinition]...) -> [any RuleDefinition] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [any RuleDefinition]?) -> [any RuleDefinition] {
        component ?? []
    }

    public static func buildEither(first component: [any RuleDefinition]) -> [any RuleDefinition] {
        component
    }

    public static func buildEither(second component: [any RuleDefinition]) -> [any RuleDefinition] {
        component
    }

    public static func buildArray(_ components: [[any RuleDefinition]]) -> [any RuleDefinition] {
        components.flatMap { $0 }
    }
}

/// One heterogeneous rule collection evaluated by one engine.
public struct RuleSet: Sendable {
    public let rules: [any RuleDefinition]

    public init(rules: [any RuleDefinition]) {
        self.rules = rules
    }

    public init(@RuleSetBuilder _ rules: () -> [any RuleDefinition]) {
        self.init(rules: rules())
    }

    public static let empty = RuleSet(rules: [])

    /// Evaluates every rule over one parsed repository. The engine owns
    /// context construction, so every run has one repository and one fact
    /// cache. Analysis errors are not violations: a throwing rule aborts
    /// the run with an explicit error.
    public func evaluate(
        configuration: ArchitectureConfiguration,
        repository: RepositorySyntax
    ) throws -> RuleReport {
        try evaluationRun(configuration: configuration, repository: repository).report
    }

    /// The same evaluation, keeping its telemetry: per-rule and per-fact
    /// durations for diagnosing slow project rules.
    public func evaluationRun(
        configuration: ArchitectureConfiguration,
        repository: RepositorySyntax
    ) throws -> EvaluationRun {
        try evaluationRun(in: RuleContext(configuration: configuration, repository: repository))
    }

    func evaluate(in context: RuleContext) throws -> RuleReport {
        try evaluationRun(in: context).report
    }

    func evaluationRun(in context: RuleContext) throws -> EvaluationRun {
        let clock = ContinuousClock()
        let runStart = clock.now
        try validateRuleIdentity()

        var ruleSeconds: [EvaluationTelemetry.Measurement] = []
        var collected: [RuleViolation] = []
        for rule in rules {
            let ruleStart = clock.now
            collected += try Self.violations(of: rule, in: context)
            ruleSeconds.append(
                EvaluationTelemetry.Measurement(
                    id: rule.metadata.id.rawValue,
                    seconds: (clock.now - ruleStart).secondsValue
                )
            )
        }

        return EvaluationRun(
            report: RuleReport(violations: collected.deterministicallySorted()),
            telemetry: EvaluationTelemetry(
                ruleSeconds: ruleSeconds,
                factSeconds: context.factMeasurements(),
                totalSeconds: (clock.now - runStart).secondsValue
            )
        )
    }

    /// Duplicate rule IDs are a configuration error, not last-writer-wins.
    private func validateRuleIdentity() throws {
        var seen = Set<RuleID>()
        for rule in rules {
            guard seen.insert(rule.metadata.id).inserted else {
                throw RuleEvaluationError.duplicateRuleID(rule.metadata.id)
            }
        }
    }

    private static func violations(of rule: any RuleDefinition, in context: RuleContext) throws -> [RuleViolation] {
        do {
            return try rule.evaluate(in: context).map { failure in
                RuleViolation(rule: rule.metadata, failure: failure)
            }
        } catch let error as RuleEvaluationError {
            throw error
        } catch {
            throw RuleEvaluationError.ruleFailed(rule.metadata.id, String(describing: error))
        }
    }
}

/// Explicit analysis failures. Never converted into empty match sets.
public enum RuleEvaluationError: Error, Equatable, Sendable, CustomStringConvertible {
    case ruleFailed(RuleID, String)
    case missingSource(RelativeFilePath)
    case missingConfiguredOwner(RuleID, String)
    case duplicateRuleID(RuleID)
    case emptyRuleScope(RuleID)
    case invalidSyntaxCardinality(RuleID, Int)

    public var description: String {
        switch self {
        case .ruleFailed(let id, let message):
            "Rule \(id.rawValue) failed to evaluate: \(message)"
        case .missingSource(let path):
            "Source text is unavailable for \(path.rawValue); rules over syntax cannot evaluate."
        case .missingConfiguredOwner(let id, let owner):
            "Rule \(id.rawValue) requires configured owner files under \(owner), but none exist."
        case .duplicateRuleID(let id):
            "Rule ID \(id.rawValue) is declared more than once; rule IDs must be unique."
        case .emptyRuleScope(let id):
            "Rule \(id.rawValue) requires syntax matches, but its scope selects no files."
        case .invalidSyntaxCardinality(let id, let count):
            "Rule \(id.rawValue) has a negative syntax cardinality (\(count)); counts must be nonnegative."
        }
    }
}
