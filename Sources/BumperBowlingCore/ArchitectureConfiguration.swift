import Foundation
import SwiftSyntax

public struct ArchitectureConfiguration: Equatable, Sendable, Codable {
    public let includedPaths: [String]
    public let excludedPaths: [String]
    public let components: [ComponentConfiguration]
    public let rules: RuleConfiguration

    public init(
        includedPaths: [String] = ["Sources"],
        excludedPaths: [String] = [".build", "DerivedData"],
        components: [ComponentConfiguration],
        rules: RuleConfiguration = RuleConfiguration()
    ) {
        self.includedPaths = includedPaths
        self.excludedPaths = excludedPaths
        self.components = components
        self.rules = rules
    }
}

public struct ComponentConfiguration: Equatable, Sendable, Codable {
    public let name: String
    public let modules: [String]
    public let paths: [String]
    public let mayDependOn: [String]
    public let mustNotDependOn: [String]

    public init(
        name: String,
        modules: [String] = [],
        paths: [String],
        mayDependOn: [String] = [],
        mustNotDependOn: [String] = []
    ) {
        self.name = name
        self.modules = modules
        self.paths = paths
        self.mayDependOn = mayDependOn
        self.mustNotDependOn = mustNotDependOn
    }
}

public struct RuleConfiguration: Equatable, Sendable, Codable {
    public let forbiddenImports: [RuleSetting]
    public let componentBoundary: Severity
    public let duplicateOwnership: Severity
    public let sourceCoverage: Severity?
    public let declaredDependencyCycle: Severity
    public let storedProperties: StoredPropertyRuleConfiguration
    public let storedPropertyRules: [StoredPropertyRuleConfiguration]
    public let syntaxConstructs: SyntaxConstructRuleConfiguration
    public let syntaxConstructRules: [SyntaxConstructRuleConfiguration]
    public let syntaxKinds: SyntaxKindRuleConfiguration
    public let syntaxKindRules: [SyntaxKindRuleConfiguration]
    public let syntaxNodes: SyntaxNodeRuleConfiguration
    public let syntaxNodeRules: [SyntaxNodeRuleConfiguration]
    public let publicDeclarations: PublicDeclarationRuleConfiguration
    public let publicDeclarationRules: [PublicDeclarationRuleConfiguration]
    public let enumStateMachine: PathRuleConfiguration
    public let enumStateMachineRules: [PathRuleConfiguration]

    public init(
        forbiddenImports: RuleSetting = RuleSetting(severity: .off, values: []),
        componentBoundary: Severity = .off,
        duplicateOwnership: Severity = .off,
        sourceCoverage: Severity? = nil,
        declaredDependencyCycle: Severity = .off,
        storedProperties: StoredPropertyRuleConfiguration = StoredPropertyRuleConfiguration(),
        syntaxConstructs: SyntaxConstructRuleConfiguration = SyntaxConstructRuleConfiguration(),
        syntaxKinds: SyntaxKindRuleConfiguration = SyntaxKindRuleConfiguration(),
        syntaxNodes: SyntaxNodeRuleConfiguration = SyntaxNodeRuleConfiguration(),
        publicDeclarations: PublicDeclarationRuleConfiguration = PublicDeclarationRuleConfiguration(),
        enumStateMachine: PathRuleConfiguration = PathRuleConfiguration(),
        storedPropertyRules: [StoredPropertyRuleConfiguration] = [],
        syntaxConstructRules: [SyntaxConstructRuleConfiguration] = [],
        syntaxKindRules: [SyntaxKindRuleConfiguration] = [],
        syntaxNodeRules: [SyntaxNodeRuleConfiguration] = [],
        publicDeclarationRules: [PublicDeclarationRuleConfiguration] = [],
        enumStateMachineRules: [PathRuleConfiguration] = []
    ) {
        self.init(
            forbiddenImports: forbiddenImports.isConfigured ? [forbiddenImports] : [],
            componentBoundary: componentBoundary,
            duplicateOwnership: duplicateOwnership,
            sourceCoverage: sourceCoverage,
            declaredDependencyCycle: declaredDependencyCycle,
            storedProperties: storedProperties,
            syntaxConstructs: syntaxConstructs,
            syntaxKinds: syntaxKinds,
            syntaxNodes: syntaxNodes,
            publicDeclarations: publicDeclarations,
            enumStateMachine: enumStateMachine,
            storedPropertyRules: storedPropertyRules,
            syntaxConstructRules: syntaxConstructRules,
            syntaxKindRules: syntaxKindRules,
            syntaxNodeRules: syntaxNodeRules,
            publicDeclarationRules: publicDeclarationRules,
            enumStateMachineRules: enumStateMachineRules
        )
    }

    public init(
        forbiddenImports: [RuleSetting],
        componentBoundary: Severity = .off,
        duplicateOwnership: Severity = .off,
        sourceCoverage: Severity? = nil,
        declaredDependencyCycle: Severity = .off,
        storedProperties: StoredPropertyRuleConfiguration = StoredPropertyRuleConfiguration(),
        syntaxConstructs: SyntaxConstructRuleConfiguration = SyntaxConstructRuleConfiguration(),
        syntaxKinds: SyntaxKindRuleConfiguration = SyntaxKindRuleConfiguration(),
        syntaxNodes: SyntaxNodeRuleConfiguration = SyntaxNodeRuleConfiguration(),
        publicDeclarations: PublicDeclarationRuleConfiguration = PublicDeclarationRuleConfiguration(),
        enumStateMachine: PathRuleConfiguration = PathRuleConfiguration(),
        storedPropertyRules: [StoredPropertyRuleConfiguration] = [],
        syntaxConstructRules: [SyntaxConstructRuleConfiguration] = [],
        syntaxKindRules: [SyntaxKindRuleConfiguration] = [],
        syntaxNodeRules: [SyntaxNodeRuleConfiguration] = [],
        publicDeclarationRules: [PublicDeclarationRuleConfiguration] = [],
        enumStateMachineRules: [PathRuleConfiguration] = []
    ) {
        let storedPropertyRules = Self.configured([storedProperties] + storedPropertyRules)
        let syntaxConstructRules = Self.configured([syntaxConstructs] + syntaxConstructRules)
        let syntaxKindRules = Self.configured([syntaxKinds] + syntaxKindRules)
        let syntaxNodeRules = Self.configured([syntaxNodes] + syntaxNodeRules)
        let publicDeclarationRules = Self.configured([publicDeclarations] + publicDeclarationRules)
        let enumStateMachineRules = Self.configured([enumStateMachine] + enumStateMachineRules)

        self.forbiddenImports = forbiddenImports.filter(\.isConfigured)
        self.componentBoundary = componentBoundary
        self.duplicateOwnership = duplicateOwnership
        self.sourceCoverage = sourceCoverage
        self.declaredDependencyCycle = declaredDependencyCycle
        self.storedPropertyRules = storedPropertyRules
        self.storedProperties = Self.combined(storedPropertyRules)
        self.syntaxConstructRules = syntaxConstructRules
        self.syntaxConstructs = Self.combined(syntaxConstructRules)
        self.syntaxKindRules = syntaxKindRules
        self.syntaxKinds = Self.combined(syntaxKindRules)
        self.syntaxNodeRules = syntaxNodeRules
        self.syntaxNodes = Self.combined(syntaxNodeRules)
        self.publicDeclarationRules = publicDeclarationRules
        self.publicDeclarations = Self.combined(publicDeclarationRules)
        self.enumStateMachineRules = enumStateMachineRules
        self.enumStateMachine = Self.combined(enumStateMachineRules)
    }
}

public struct RuleSetting: Equatable, Sendable, Codable {
    public let severity: Severity
    public let values: [String]
    public let paths: [String]

    public init(severity: Severity, values: [String], paths: [String] = []) {
        self.severity = severity
        self.values = values
        self.paths = paths
    }

    var isConfigured: Bool {
        severity != .off || !values.isEmpty || !paths.isEmpty
    }
}

public struct StoredPropertyRuleConfiguration: Equatable, Sendable, Codable {
    public let severity: Severity
    public let paths: [String]
    public let excludedPaths: [String]
    public let disallowances: Set<StoredPropertyDisallowance>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        excludedPaths: [String] = [],
        disallowances: Set<StoredPropertyDisallowance> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.excludedPaths = excludedPaths
        self.disallowances = disallowances
    }
}

public struct SyntaxConstructRuleConfiguration: Equatable, Sendable, Codable {
    public let severity: Severity
    public let paths: [String]
    public let excludedPaths: [String]
    public let disallowedConstructs: Set<ImperativeConstruct>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        excludedPaths: [String] = [],
        disallowedConstructs: Set<ImperativeConstruct> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.excludedPaths = excludedPaths
        self.disallowedConstructs = disallowedConstructs
    }
}

public struct SyntaxKindRuleConfiguration: Equatable, Sendable, Codable {
    public let severity: Severity
    public let paths: [String]
    public let requiredKinds: Set<SyntaxKindName>
    public let disallowedKinds: Set<SyntaxKindName>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        requiredKinds: Set<SyntaxKind> = [],
        disallowedKinds: Set<SyntaxKind> = []
    ) {
        self.init(
            severity: severity,
            paths: paths,
            requiredKinds: Set(requiredKinds.map(SyntaxKindName.init)),
            disallowedKinds: Set(disallowedKinds.map(SyntaxKindName.init))
        )
    }

    public init(
        severity: Severity,
        paths: [String],
        requiredKinds: Set<SyntaxKindName>,
        disallowedKinds: Set<SyntaxKindName>
    ) {
        self.severity = severity
        self.paths = paths
        self.requiredKinds = requiredKinds
        self.disallowedKinds = disallowedKinds
    }
}

public struct SyntaxKindName: Hashable, Sendable, CustomStringConvertible, Codable {
    public let rawValue: String

    public init(_ kind: SyntaxKind) {
        self.rawValue = String(describing: kind)
    }

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptySyntaxKindName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SyntaxNodeMatcher: Hashable, Sendable, CustomStringConvertible, Codable {
    public let kind: SyntaxKindName?
    public let spelling: StringMatcher?
    public let parentKind: SyntaxKindName?
    public let ancestorKind: SyntaxKindName?

    public init(
        kind: SyntaxKind? = nil,
        spelling: StringMatcher? = nil,
        parentKind: SyntaxKind? = nil,
        ancestorKind: SyntaxKind? = nil
    ) {
        self.kind = kind.map(SyntaxKindName.init)
        self.spelling = spelling
        self.parentKind = parentKind.map(SyntaxKindName.init)
        self.ancestorKind = ancestorKind.map(SyntaxKindName.init)
    }

    public static func kind(_ kind: SyntaxKind) -> SyntaxNodeMatcher {
        SyntaxNodeMatcher(kind: kind)
    }

    public static func spelling(_ spelling: StringMatcher) -> SyntaxNodeMatcher {
        SyntaxNodeMatcher(spelling: spelling)
    }

    public var description: String {
        [
            kind.map { "kind=\($0.rawValue)" },
            spelling.map { "spelling=\($0.description)" },
            parentKind.map { "parent=\($0.rawValue)" },
            ancestorKind.map { "ancestor=\($0.rawValue)" }
        ].compactMap { $0 }.joined(separator: ", ")
    }
}

public struct SyntaxNodeRuleConfiguration: Equatable, Sendable, Codable {
    public let severity: Severity
    public let paths: [String]
    public let requiredNodes: Set<SyntaxNodeMatcher>
    public let disallowedNodes: Set<SyntaxNodeMatcher>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        requiredNodes: Set<SyntaxNodeMatcher> = [],
        disallowedNodes: Set<SyntaxNodeMatcher> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.requiredNodes = requiredNodes
        self.disallowedNodes = disallowedNodes
    }
}

extension SyntaxNodeMatcher {
    func matches(_ node: ObservedSyntaxNode) -> Bool {
        if let kind, kind != SyntaxKindName(node.kind) {
            return false
        }

        if let parentKind, parentKind != node.parentKind.map(SyntaxKindName.init) {
            return false
        }

        if let ancestorKind,
           !node.ancestorKinds.map(SyntaxKindName.init).contains(ancestorKind) {
            return false
        }

        if let spelling {
            guard let nodeSpelling = node.spelling, spelling.matches(nodeSpelling) else {
                return false
            }
        }

        return true
    }
}

public struct PublicDeclarationRuleConfiguration: Equatable, Sendable, Codable {
    public let severity: Severity
    public let paths: [String]
    public let requiredNames: Set<StringMatcher>
    public let disallowedNames: Set<StringMatcher>

    public init(
        severity: Severity = .off,
        paths: [String] = [],
        requiredNames: Set<StringMatcher> = [],
        disallowedNames: Set<StringMatcher> = []
    ) {
        self.severity = severity
        self.paths = paths
        self.requiredNames = requiredNames
        self.disallowedNames = disallowedNames
    }
}

public struct PathRuleConfiguration: Equatable, Sendable, Codable {
    public let severity: Severity
    public let paths: [String]

    public init(severity: Severity = .off, paths: [String] = []) {
        self.severity = severity
        self.paths = paths
    }
}

extension StoredPropertyRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !excludedPaths.isEmpty || !disallowances.isEmpty
    }
}

extension SyntaxConstructRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !excludedPaths.isEmpty || !disallowedConstructs.isEmpty
    }
}

extension SyntaxKindRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !requiredKinds.isEmpty || !disallowedKinds.isEmpty
    }
}

extension SyntaxNodeRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !requiredNodes.isEmpty || !disallowedNodes.isEmpty
    }
}

extension PublicDeclarationRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty || !requiredNames.isEmpty || !disallowedNames.isEmpty
    }
}

extension PathRuleConfiguration {
    var isConfigured: Bool {
        severity != .off || !paths.isEmpty
    }
}

private extension RuleConfiguration {
    static func configured(_ configurations: [StoredPropertyRuleConfiguration]) -> [StoredPropertyRuleConfiguration] {
        configurations.filter(\.isConfigured)
    }

    static func configured(_ configurations: [SyntaxConstructRuleConfiguration]) -> [SyntaxConstructRuleConfiguration] {
        configurations.filter(\.isConfigured)
    }

    static func configured(_ configurations: [SyntaxKindRuleConfiguration]) -> [SyntaxKindRuleConfiguration] {
        configurations.filter(\.isConfigured)
    }

    static func configured(_ configurations: [SyntaxNodeRuleConfiguration]) -> [SyntaxNodeRuleConfiguration] {
        configurations.filter(\.isConfigured)
    }

    static func configured(_ configurations: [PublicDeclarationRuleConfiguration]) -> [PublicDeclarationRuleConfiguration] {
        configurations.filter(\.isConfigured)
    }

    static func configured(_ configurations: [PathRuleConfiguration]) -> [PathRuleConfiguration] {
        configurations.filter(\.isConfigured)
    }

    static func combined(_ configurations: [StoredPropertyRuleConfiguration]) -> StoredPropertyRuleConfiguration {
        configurations.reduce(StoredPropertyRuleConfiguration()) { partialResult, configuration in
            StoredPropertyRuleConfiguration(
                severity: partialResult.severity.merging(configuration.severity),
                paths: Array(Set(partialResult.paths + configuration.paths)).sorted(),
                excludedPaths: Array(Set(partialResult.excludedPaths + configuration.excludedPaths)).sorted(),
                disallowances: partialResult.disallowances.union(configuration.disallowances)
            )
        }
    }

    static func combined(_ configurations: [SyntaxConstructRuleConfiguration]) -> SyntaxConstructRuleConfiguration {
        configurations.reduce(SyntaxConstructRuleConfiguration()) { partialResult, configuration in
            SyntaxConstructRuleConfiguration(
                severity: partialResult.severity.merging(configuration.severity),
                paths: Array(Set(partialResult.paths + configuration.paths)).sorted(),
                excludedPaths: Array(Set(partialResult.excludedPaths + configuration.excludedPaths)).sorted(),
                disallowedConstructs: partialResult.disallowedConstructs.union(configuration.disallowedConstructs)
            )
        }
    }

    static func combined(_ configurations: [SyntaxKindRuleConfiguration]) -> SyntaxKindRuleConfiguration {
        configurations.reduce(SyntaxKindRuleConfiguration()) { partialResult, configuration in
            SyntaxKindRuleConfiguration(
                severity: partialResult.severity.merging(configuration.severity),
                paths: Array(Set(partialResult.paths + configuration.paths)).sorted(),
                requiredKinds: partialResult.requiredKinds.union(configuration.requiredKinds),
                disallowedKinds: partialResult.disallowedKinds.union(configuration.disallowedKinds)
            )
        }
    }

    static func combined(_ configurations: [SyntaxNodeRuleConfiguration]) -> SyntaxNodeRuleConfiguration {
        configurations.reduce(SyntaxNodeRuleConfiguration()) { partialResult, configuration in
            SyntaxNodeRuleConfiguration(
                severity: partialResult.severity.merging(configuration.severity),
                paths: Array(Set(partialResult.paths + configuration.paths)).sorted(),
                requiredNodes: partialResult.requiredNodes.union(configuration.requiredNodes),
                disallowedNodes: partialResult.disallowedNodes.union(configuration.disallowedNodes)
            )
        }
    }

    static func combined(_ configurations: [PublicDeclarationRuleConfiguration]) -> PublicDeclarationRuleConfiguration {
        configurations.reduce(PublicDeclarationRuleConfiguration()) { partialResult, configuration in
            PublicDeclarationRuleConfiguration(
                severity: partialResult.severity.merging(configuration.severity),
                paths: Array(Set(partialResult.paths + configuration.paths)).sorted(),
                requiredNames: partialResult.requiredNames.union(configuration.requiredNames),
                disallowedNames: partialResult.disallowedNames.union(configuration.disallowedNames)
            )
        }
    }

    static func combined(_ configurations: [PathRuleConfiguration]) -> PathRuleConfiguration {
        configurations.reduce(PathRuleConfiguration()) { partialResult, configuration in
            PathRuleConfiguration(
                severity: partialResult.severity.merging(configuration.severity),
                paths: Array(Set(partialResult.paths + configuration.paths)).sorted()
            )
        }
    }
}

public enum StoredPropertyDisallowance: String, Equatable, Hashable, Sendable, Codable {
    case any
    case boolState
    case broadExistential
    case optionalState
    case storedProperty
    case storedVar
    case rawStringIdentity
}

extension Severity {
    func merging(_ other: Severity) -> Severity {
        switch (self, other) {
        case (.error, _), (_, .error):
            .error
        case (.warning, _), (_, .warning):
            .warning
        case (.note, _), (_, .note):
            .note
        case (.off, .off):
            .off
        }
    }
}

public enum ConfigurationLoader {
    public static let fileName = "BumperBowling.swift"

    public static func writeSample(to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw BumperError.configurationAlreadyExists(url.path)
        }

        try Self.sampleDSL.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let sampleDSL = """
    import BumperBowlingCore

    // Bumper Bowling compiles this file into the project runner, like
    // SwiftPM compiles Package.swift. `bumper` is the one project entry
    // point: scan paths, architecture, and rules.
    enum AppComponent: String, ComponentKey {
        case app
    }

    let bumper = BumperProject {
        Included {
            "Sources"
        }

        Excluded {
            ".build"
            "DerivedData"
        }

        Architecture(AppComponent.self) {
            Component(.app) {
                Owns("Sources")
                Modules("App")
                MayUse(.foundation)
                Requires(
                    .explicitDomainSurfaces,
                    .typedIdentity,
                    .immutableStoredState,
                    severity: .warning
                )
            }
        }

        Rules {
            DependencyBoundaries(.error)
            SingleOwner(.error)
            SourceCoverage(.error)
            AcyclicDeclaredDependencies(.error)
        }
    }
    """
}
