import Foundation
import SwiftLintFramework

public struct RuleMetadata: Sendable {
    public let id: String
    public let summary: String
    public let severity: ViolationSeverity

    public init(id: String, summary: String, severity: ViolationSeverity = .error) {
        self.id = id
        self.summary = summary
        self.severity = severity
    }
}

/// The native configuration carries repository identity, not executable policy.
/// Rule settings and predicates are reviewed Swift source.
public struct RuleSettings<Parent: Rule>: RuleConfiguration {
    public private(set) var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    public init() {}
    public mutating func apply(configuration: Any) throws(Issue) {
        guard let dictionary = configuration as? [String: String], dictionary.count == 1,
              let path = dictionary["repository_root"], path.hasPrefix("/") else {
            throw .invalidConfiguration(ruleID: Parent.identifier)
        }
        root = URL(fileURLWithPath: path)
    }
}

/// Every DSL rule is its own native SwiftLint rule type and keeps its own ID.
public protocol BumperRule: SourceKitFreeRule where ConfigurationType == RuleSettings<Self> {
    static var metadata: RuleMetadata { get }
    var scope: RuleScope { get }
    func checkInput(_ files: [SourceFileContext]) throws
}

public extension BumperRule {
    static var description: RuleDescription {
        RuleDescription(identifier: metadata.id, name: metadata.id, description: metadata.summary, kind: .lint)
    }

    var shouldLintEmptyFiles: Bool { true }
    var scope: RuleScope { .repository }
    func checkInput(_ files: [SourceFileContext]) throws { try scope.validate() }

    func violations(from failures: [RuleFailure]) -> [StyleViolation] {
        failures.map {
            StyleViolation(ruleDescription: Self.description, severity: Self.metadata.severity, location: $0.location, reason: $0.message)
        }
    }
}

public protocol SyntaxRule: BumperRule {
    var body: SyntaxCheck { get }
}

public extension SyntaxRule {
    var scope: RuleScope { body.scope }
    func validate(file: SwiftLintFile) -> [StyleViolation] {
        let context = SourceFileContext(file: file, root: configuration.root)
        return scope.includes(context) ? violations(from: body.check(context)) : []
    }
}

public protocol RepositoryRule: BumperRule, CollectingRule where FileInfo: Sendable {
    var body: RepositoryCheck<FileInfo> { get }
}

public extension RepositoryRule {
    var scope: RuleScope { body.scope }
    func collectInfo(for file: SwiftLintFile) -> FileInfo {
        body.collect(SourceFileContext(file: file, root: configuration.root))
    }

    func validate(file: SwiftLintFile, collectedInfo: [SwiftLintFile: FileInfo]) -> [StyleViolation] {
        let context = SourceFileContext(file: file, root: configuration.root)
        guard body.scope.includes(context) else { return [] }
        let inventory = collectedInfo.sorted { ($0.key.path ?? "") < ($1.key.path ?? "") }.map(\.value)
        return violations(from: body.check(context, inventory))
    }

    func checkInput(_ files: [SourceFileContext]) throws {
        try scope.validate()
        guard files.contains(where: body.scope.includes) else {
            throw BumperError("\(Self.metadata.id) selected no subject files.")
        }
    }
}

public struct SyntaxCheck: Sendable {
    let scope: RuleScope
    let check: @Sendable (SourceFileContext) -> [RuleFailure]
}

public struct RepositoryCheck<Info>: Sendable {
    let scope: RuleScope
    let collect: @Sendable (SourceFileContext) -> Info
    let check: @Sendable (SourceFileContext, [Info]) -> [RuleFailure]
}

/// Composable syntax policies; SwiftLint owns scheduling, parsing, and collection.
public enum Rules {
    public static func forbid<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        scope: RuleScope = .repository,
        _ message: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> String
    ) -> SyntaxCheck {
        each(pattern, scope: scope) { [$0.failure(message: message($0))] }
    }

    public static func each<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        scope: RuleScope = .repository,
        _ check: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> [RuleFailure]
    ) -> SyntaxCheck {
        files(scope: scope) { pattern.matches(in: $0).flatMap(check) }
    }

    public static func files(
        scope: RuleScope = .repository,
        _ check: @escaping @Sendable (SourceFileContext) -> [RuleFailure]
    ) -> SyntaxCheck {
        SyntaxCheck(scope: scope, check: check)
    }

    public static func repository<Info>(
        scope: RuleScope = .repository,
        collect: @escaping @Sendable (SourceFileContext) -> Info,
        check: @escaping @Sendable (SourceFileContext, [Info]) -> [RuleFailure]
    ) -> RepositoryCheck<Info> {
        RepositoryCheck(scope: scope, collect: collect, check: check)
    }
}
