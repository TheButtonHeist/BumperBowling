import BumperBowlingCore
import Foundation
import SwiftLintFramework

/// Path-aware examples, evaluated by the same native SwiftLint path as production.
public struct RuleTestHarness: Sendable {
    private let rules: [any Rule.Type]

    public init<Author: SyntaxRule>(_ rule: Author.Type) { self.rules = BumperProject { rule }.rules }
    public init<Author: RepositoryRule>(_ rule: Author.Type) { self.rules = BumperProject { rule }.rules }
    public init(@RuleSetBuilder _ rules: () -> [any Rule.Type]) { self.rules = rules() }
    public init(_ rule: any Rule.Type) { self.rules = [rule] }
    public init(_ rules: [any Rule.Type]) { self.rules = rules }

    public func evaluate(_ sources: [SourceInput]) throws -> [StyleViolation] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bumper-fixtures-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var paths: Set<String> = []
        for source in sources {
            guard !source.path.isEmpty, !source.path.hasPrefix("/"), !source.path.contains("\\"),
                  source.path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  source.path.hasSuffix(".swift"), paths.insert(source.path).inserted else {
                throw BumperError("Invalid or duplicate Swift fixture path: \(source.path)")
            }
            let url = root.appendingPathComponent(source.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(source.source.utf8).write(to: url)
        }
        if sources.isEmpty { return try BumperRunner.evaluate(rules, files: [], root: root) }
        return try BumperRunner.lint(rules, root: root, included: sources.map(\.path))
    }
}
