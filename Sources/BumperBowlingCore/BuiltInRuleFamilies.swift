import Foundation

/// One configured built-in rule family. Internal evaluation currency only:
/// the public surface is `BuiltInRules` producing ordinary `RuleDefinition`s.
enum ArchitectureRule: Sendable {
    case forbiddenImport([RuleSetting])
    case componentBoundary(Severity)
    case duplicateOwnership(Severity)
    case sourceCoverage(Severity)
    case declaredDependencyCycle(Severity)
    case storedProperties(StoredPropertyRuleConfiguration)
    case syntaxConstructs(SyntaxConstructRuleConfiguration)
    case syntaxKinds(SyntaxKindRuleConfiguration)
    case syntaxNodes(SyntaxNodeRuleConfiguration)
    case publicDeclarations(PublicDeclarationRuleConfiguration)
    case enumStateMachine(PathRuleConfiguration)

    var id: RuleID {
        switch self {
        case .forbiddenImport:
            .forbiddenImport
        case .componentBoundary:
            .componentBoundary
        case .sourceCoverage:
            .sourceCoverage
        case .duplicateOwnership:
            .duplicateOwnership
        case .declaredDependencyCycle:
            .declaredDependencyCycle
        case .storedProperties:
            .storedProperties
        case .syntaxConstructs:
            .syntaxConstructs
        case .syntaxKinds:
            .syntaxKinds
        case .syntaxNodes:
            .syntaxNodes
        case .publicDeclarations:
            .publicDeclarations
        case .enumStateMachine:
            .enumStateMachine
        }
    }

    var description: String {
        switch self {
        case .forbiddenImport:
            "Disallows configured imports in linted source files."
        case .componentBoundary:
            "Requires component imports to match declared dependencies."
        case .sourceCoverage:
            "Requires exactly one owner for each included Swift source and reports scan coverage gaps."
        case .duplicateOwnership:
            "Disallows duplicate component path and module ownership."
        case .declaredDependencyCycle:
            "Disallows cycles in declared component dependencies."
        case .storedProperties:
            "Applies configured assertions over SwiftSyntax stored property facts."
        case .syntaxConstructs:
            "Applies configured assertions over SwiftSyntax construct facts."
        case .syntaxKinds:
            "Applies configured assertions over observed SwiftSyntax node kinds."
        case .syntaxNodes:
            "Applies configured assertions over observed SwiftSyntax nodes."
        case .publicDeclarations:
            "Applies configured assertions over public declaration facts."
        case .enumStateMachine:
            "Requires parser files to declare an enum state machine."
        }
    }

    var isEnabled: Bool {
        configuredSeverity != .off
    }

    var configuredSeverity: Severity {
        switch self {
        case .forbiddenImport(let settings):
            settings.map(\.severity).reduce(.off) { partialResult, severity in
                partialResult.merging(severity)
            }
        case .componentBoundary(let severity):
            severity
        case .sourceCoverage(let severity):
            severity
        case .duplicateOwnership(let severity):
            severity
        case .declaredDependencyCycle(let severity):
            severity
        case .storedProperties(let configuration):
            configuration.severity
        case .syntaxConstructs(let configuration):
            configuration.severity
        case .syntaxKinds(let configuration):
            configuration.severity
        case .syntaxNodes(let configuration):
            configuration.severity
        case .publicDeclarations(let configuration):
            configuration.severity
        case .enumStateMachine(let configuration):
            configuration.severity
        }
    }

    func evaluate(graph: ArchitectureGraph, rules: ArchitectureRules) -> [RuleFailure] {
        switch self {
        case .forbiddenImport(let settings):
            evaluateForbiddenImports(graph: graph, settings: settings)
        case .componentBoundary(let severity):
            evaluateComponentBoundaries(graph: graph, rules: rules, severity: severity)
        case .sourceCoverage(let severity):
            graph.coverage?.failures(severity: severity) ?? []
        case .duplicateOwnership(let severity):
            evaluateDuplicateOwnership(rules: rules, severity: severity)
        case .declaredDependencyCycle(let severity):
            evaluateDeclaredDependencyCycles(graph: graph, rules: rules, severity: severity)
        case .storedProperties(let configuration):
            evaluateStoredProperties(graph: graph, configuration: configuration)
        case .syntaxConstructs(let configuration):
            evaluateSyntaxConstructs(graph: graph, configuration: configuration)
        case .syntaxKinds(let configuration):
            evaluateSyntaxKinds(graph: graph, configuration: configuration)
        case .syntaxNodes(let configuration):
            evaluateSyntaxNodes(graph: graph, configuration: configuration)
        case .publicDeclarations(let configuration):
            evaluatePublicDeclarations(graph: graph, configuration: configuration)
        case .enumStateMachine(let configuration):
            evaluateEnumStateMachines(graph: graph, configuration: configuration)
        }
    }

}

extension RelativePathPrefix {
    var asFilePath: RelativeFilePath? {
        try? RelativeFilePath(rawValue)
    }
}

public struct ViolationEvidence: Equatable, Sendable, Codable {
    public let observed: String
    public let expectation: String
    /// Project-specific named details, kept in deterministic name order.
    public let details: [EvidenceDetail]

    public init(observed: String, expectation: String, details: [EvidenceDetail] = []) {
        self.observed = observed
        self.expectation = expectation
        self.details = details.sorted { lhs, rhs in lhs.name < rhs.name }
    }

    private enum CodingKeys: String, CodingKey {
        case observed
        case expectation
        case details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            observed: try container.decode(String.self, forKey: .observed),
            expectation: try container.decode(String.self, forKey: .expectation),
            details: try container.decodeIfPresent([EvidenceDetail].self, forKey: .details) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observed, forKey: .observed)
        try container.encode(expectation, forKey: .expectation)
        if !details.isEmpty {
            try container.encode(details, forKey: .details)
        }
    }
}

public struct EvidenceDetail: Equatable, Sendable, Codable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct RuleID: Hashable, RawRepresentable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let forbiddenImport = RuleID("forbidden_import")
    public static let componentBoundary = RuleID("component_boundary")
    public static let sourceCoverage = RuleID("source_coverage")
    public static let duplicateOwnership = RuleID("duplicate_ownership")
    public static let declaredDependencyCycle = RuleID("declared_dependency_cycle")
    public static let storedProperties = RuleID("stored_properties")
    public static let syntaxConstructs = RuleID("syntax_constructs")
    public static let syntaxKinds = RuleID("syntax_kinds")
    public static let syntaxNodes = RuleID("syntax_nodes")
    public static let publicDeclarations = RuleID("public_declarations")
    public static let enumStateMachine = RuleID("enum_state_machine")
}

public enum Severity: String, Equatable, Sendable, Codable {
    case off
    case note
    case warning
    case error
}
