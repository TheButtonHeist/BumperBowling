import Foundation
import SwiftLintFramework
import SwiftSyntax

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

/// A repository convention, hosted as a distinct native SwiftLint rule.
public protocol SyntaxRule {
    static var metadata: RuleMetadata { get }
    @CheckBuilder static var body: SyntaxCheck { get }
}

/// Collects typed observations from all scanned files before checking subjects.
public protocol RepositoryRule {
    associatedtype FileInfo: Sendable
    static var metadata: RuleMetadata { get }
    static var body: RepositoryCheck<FileInfo> { get }
}

/// Carries repository identity through SwiftLint's native configuration.
struct RuleSettings<Parent: Rule>: RuleConfiguration {
    private(set) var root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    mutating func apply(configuration: Any) throws(Issue) {
        guard let dictionary = configuration as? [String: String], dictionary.count == 1,
              let path = dictionary["repository_root"], path.hasPrefix("/") else {
            throw .invalidConfiguration(ruleID: Parent.identifier)
        }
        root = URL(fileURLWithPath: path)
    }
}

protocol NativeBumperRule: SourceKitFreeRule where ConfigurationType == RuleSettings<Self> {
    static var metadata: RuleMetadata { get }
    var scope: RuleScope { get }
    func checkInput(_ files: [SourceFileContext]) throws
}

extension NativeBumperRule {
    static var description: RuleDescription {
        RuleDescription(identifier: metadata.id, name: metadata.id, description: metadata.summary, kind: .lint)
    }

    var shouldLintEmptyFiles: Bool { true }
    func checkInput(_ files: [SourceFileContext]) throws { try scope.validate() }

    func violations(from failures: [RuleFailure]) -> [StyleViolation] {
        failures.map {
            StyleViolation(ruleDescription: Self.description, severity: Self.metadata.severity, location: $0.location, reason: $0.message)
        }
    }
}

// Each specialization retains its own native identity and collection storage.
struct NativeSyntaxRule<Author: SyntaxRule>: NativeBumperRule {
    var configuration = RuleSettings<Self>()
    let body = Author.body
    static var metadata: RuleMetadata { Author.metadata }
    var scope: RuleScope { body.scope }
    func validate(file: SwiftLintFile) -> [StyleViolation] {
        violations(from: body.check(SourceFileContext(file: file, root: configuration.root)))
    }
}

struct NativeRepositoryRule<Author: RepositoryRule>: NativeBumperRule, CollectingRule {
    typealias FileInfo = Author.FileInfo
    var configuration = RuleSettings<Self>()
    let body = Author.body
    static var metadata: RuleMetadata { Author.metadata }
    var scope: RuleScope { body.scope }

    func collectInfo(for file: SwiftLintFile) -> FileInfo {
        body.collect(SourceFileContext(file: file, root: configuration.root))
    }

    func validate(file: SwiftLintFile, collectedInfo: [SwiftLintFile: FileInfo]) -> [StyleViolation] {
        let context = SourceFileContext(file: file, root: configuration.root)
        guard scope.includes(context) else { return [] }
        let inventory = collectedInfo.sorted { ($0.key.path ?? "") < ($1.key.path ?? "") }.map(\.value)
        return violations(from: body.check(context, inventory))
    }

    func checkInput(_ files: [SourceFileContext]) throws {
        try scope.validate()
        guard files.contains(where: scope.includes) else {
            throw BumperError("\(Self.metadata.id) selected no subject files.")
        }
    }
}

public struct SyntaxCheck: Sendable {
    let scope: RuleScope
    let check: @Sendable (SourceFileContext) -> [RuleFailure]

    init(scope: RuleScope, check: @escaping @Sendable (SourceFileContext) -> [RuleFailure]) {
        self.scope = scope
        self.check = { scope.includes($0) ? check($0) : [] }
    }
}

public struct RepositoryCheck<Info>: Sendable {
    let scope: RuleScope
    let collect: @Sendable (SourceFileContext) -> Info
    let check: @Sendable (SourceFileContext, [Info]) -> [RuleFailure]
}

/// Composable syntax policies; SwiftLint owns scheduling, parsing, and collection.
public enum Rules {
    /// Builds checks for each selected syntax match.
    public static func forEach<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        scope: RuleScope = .repository,
        @CheckBuilder _ checks: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> SyntaxCheck
    ) -> SyntaxCheck {
        files(scope: scope) { file in pattern.matches(in: file).flatMap { checks($0).check(file) } }
    }

    /// Reports at the subject when the condition is false.
    public static func require<Node: SyntaxProtocol>(
        _ condition: Bool, at subject: SyntaxMatch<Node>, message: String
    ) -> SyntaxCheck {
        files { _ in condition ? [] : [subject.failure(message: message)] }
    }

    /// Requires at least one companion from the subject's own syntax tree.
    public static func require<Pattern: SyntaxPattern, Node: SyntaxProtocol>(
        inSameFile pattern: Pattern, at subject: SyntaxMatch<Node>, message: String
    ) -> SyntaxCheck {
        require(pattern.hasMatch(in: subject.file), at: subject, message: message)
    }

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
        @CheckBuilder check: @escaping @Sendable (SourceFileContext, [Info]) -> SyntaxCheck
    ) -> RepositoryCheck<Info> {
        RepositoryCheck(scope: scope, collect: collect) { file, inventory in check(file, inventory).check(file) }
    }
}
