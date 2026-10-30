import Foundation
import SwiftSyntax

/// A syntax pattern's allowed number of matches in the selected counting unit.
public enum SyntaxCardinality: Equatable, Sendable, CustomStringConvertible {
    case none
    case atLeast(Int)
    case atMost(Int)
    case exactly(Int)

    public var description: String {
        switch self {
        case .none:
            "no matching syntax nodes"
        case .atLeast(let count):
            "at least \(count) matching syntax node\(count == 1 ? "" : "s")"
        case .atMost(let count):
            "at most \(count) matching syntax node\(count == 1 ? "" : "s")"
        case .exactly(let count):
            "exactly \(count) matching syntax node\(count == 1 ? "" : "s")"
        }
    }

    fileprivate var count: Int? {
        switch self {
        case .none: nil
        case .atLeast(let count), .atMost(let count), .exactly(let count): count
        }
    }

    fileprivate var requiresMatches: Bool {
        switch self {
        case .atLeast(let count), .exactly(let count): count > 0
        case .none, .atMost: false
        }
    }
}

/// File selection and match counting are independent. Repository counting
/// combines matches from every selected file.
public enum SyntaxCounting: Equatable, Sendable {
    case perFile
    case repository
}

/// One mismatch between a syntax pattern's observed and expected cardinality.
/// The match is present when a concrete node exceeds the allowed count; it is
/// absent when there are too few matches. For a repository-wide shortage,
/// `file` is the selected file with the first path in lexical order.
public struct SyntaxCardinalityViolation<Node: SyntaxProtocol>: Sendable {
    public let file: SourceFileContext
    public let match: SyntaxMatch<Node>?
    public let observedCount: Int
    public let expected: SyntaxCardinality
    public let counting: SyntaxCounting

    public func failure(message: String) -> RuleFailure {
        let evidence = ViolationEvidence(
            observed: "\(observedCount) matching syntax node\(observedCount == 1 ? "" : "s")",
            expectation: expected.description
        )

        if let match {
            return match.failure(message: message, evidence: evidence)
        }

        return RuleFailure(path: file.path, message: message, evidence: evidence)
    }
}

/// Asserts a syntax pattern's cardinality per file or across selected files.
/// Excess matches retain their own file and source location.
public struct CardinalityPattern<Pattern: SyntaxPattern>: RuleDefinition {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let pattern: Pattern
    private let cardinality: SyntaxCardinality
    private let counting: SyntaxCounting
    private let diagnostic: @Sendable (SyntaxCardinalityViolation<Pattern.Match>) -> RuleFailure

    public init(
        _ pattern: Pattern,
        cardinality: SyntaxCardinality,
        counting: SyntaxCounting = .perFile,
        metadata: RuleMetadata,
        scope: RuleScope = .repository,
        diagnostic: @escaping @Sendable (SyntaxCardinalityViolation<Pattern.Match>) -> RuleFailure
    ) {
        self.pattern = pattern
        self.cardinality = cardinality
        self.counting = counting
        self.metadata = metadata
        self.scope = scope
        self.diagnostic = diagnostic
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        if let count = cardinality.count, count < 0 {
            throw RuleEvaluationError.invalidSyntaxCardinality(metadata.id, count)
        }
        let files = context.files(in: scope).sorted { $0.path.rawValue < $1.path.rawValue }
        guard let first = files.first else {
            if cardinality.requiresMatches { throw RuleEvaluationError.emptyRuleScope(metadata.id) }
            return []
        }
        switch counting {
        case .perFile:
            return files.flatMap { file in
                violations(for: pattern.matches(in: file), in: file).map(diagnostic)
            }
        case .repository:
            return violations(for: files.flatMap { pattern.matches(in: $0) }, in: first).map(diagnostic)
        }
    }

    private func violations(
        for matches: [SyntaxMatch<Pattern.Match>],
        in file: SourceFileContext
    ) -> [SyntaxCardinalityViolation<Pattern.Match>] {
        let observedCount = matches.count
        let missingMatch: SyntaxCardinalityViolation<Pattern.Match> = .init(
            file: file,
            match: nil,
            observedCount: observedCount,
            expected: cardinality,
            counting: counting
        )

        switch cardinality {
        case .none:
            return matches.map { match in
                SyntaxCardinalityViolation(
                    file: match.file,
                    match: match,
                    observedCount: observedCount,
                    expected: cardinality,
                    counting: counting
                )
            }
        case .atLeast(let minimum):
            return observedCount < minimum ? [missingMatch] : []
        case .atMost(let maximum):
            return matches.dropFirst(maximum).map { match in
                SyntaxCardinalityViolation(
                    file: match.file,
                    match: match,
                    observedCount: observedCount,
                    expected: cardinality,
                    counting: counting
                )
            }
        case .exactly(let count):
            if observedCount < count {
                return [missingMatch]
            }

            return matches.dropFirst(count).map { match in
                SyntaxCardinalityViolation(
                    file: match.file,
                    match: match,
                    observedCount: observedCount,
                    expected: cardinality,
                    counting: counting
                )
            }
        }
    }
}

/// A rule that forbids every match of one syntax pattern.
public struct ForbiddenPattern<Pattern: SyntaxPattern>: RuleDefinition {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let pattern: Pattern
    private let diagnostic: @Sendable (SyntaxMatch<Pattern.Match>) -> RuleFailure

    public init(
        _ pattern: Pattern,
        metadata: RuleMetadata,
        scope: RuleScope = .repository,
        diagnostic: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> RuleFailure
    ) {
        self.pattern = pattern
        self.metadata = metadata
        self.scope = scope
        self.diagnostic = diagnostic
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        context.files(in: scope).flatMap { file in
            pattern.matches(in: file).map(diagnostic)
        }
    }
}

extension Rules {
    /// Evaluates arbitrary requirements for each typed syntax match. The
    /// closure can return multiple failures or throw an analysis error.
    public static func each<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        id: String,
        severity: Severity = .error,
        summary: String,
        scope: RuleScope = .repository,
        _ evaluate: @escaping @Sendable (SyntaxMatch<Pattern.Match>) throws -> [RuleFailure]
    ) -> SyntaxRule {
        files(id, severity: severity, summary: summary, scope: scope) { file in
            try pattern.matches(in: file).flatMap(evaluate)
        }
    }

    /// Counts matches per file by default, or across selected files with
    /// `.repository`. A positive requirement over an empty scope is an error.
    /// Missing matches have count evidence and no invented source location.
    public static func assert<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        cardinality: SyntaxCardinality,
        counting: SyntaxCounting = .perFile,
        id: String,
        severity: Severity = .error,
        summary: String = "Syntax pattern cardinality is constrained.",
        scope: RuleScope = .repository,
        message: @escaping @Sendable (SyntaxCardinalityViolation<Pattern.Match>) -> String = { violation in
            "Expected \(violation.expected), found \(violation.observedCount)."
        }
    ) -> CardinalityPattern<Pattern> {
        CardinalityPattern(
            pattern,
            cardinality: cardinality,
            counting: counting,
            metadata: RuleMetadata(id: RuleID(id), severity: severity, summary: summary),
            scope: scope
        ) { violation in
            violation.failure(message: message(violation))
        }
    }

    /// Concrete factory so consumers never spell generic signatures.
    public static func forbid<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        id: String,
        severity: Severity = .error,
        summary: String = "Forbidden syntax pattern.",
        scope: RuleScope = .repository,
        message: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> String
    ) -> ForbiddenPattern<Pattern> {
        ForbiddenPattern(
            pattern,
            metadata: RuleMetadata(id: RuleID(id), severity: severity, summary: summary),
            scope: scope
        ) { match in
            match.failure(message: message(match))
        }
    }
}
