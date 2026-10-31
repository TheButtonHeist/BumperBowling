import SwiftLintFramework

/// Repository-owned rule management. Every entry remains a distinct SwiftLint rule.
public struct BumperProject: Sendable {
    public let rules: [any Rule.Type]
    public let included: [String]
    public let excluded: [String]

    public init(included: [String] = ["Sources"], excluded: [String] = [], @RuleSetBuilder _ rules: () -> [any Rule.Type]) {
        self.rules = rules()
        self.included = included
        self.excluded = excluded
    }

    public func main() {
        BumperRunner.main(rules: rules, included: included, excluded: excluded)
    }
}

@resultBuilder
public enum RuleSetBuilder {
    public static func buildExpression(_ rule: any Rule.Type) -> [any Rule.Type] { [rule] }
    public static func buildBlock(_ rules: [any Rule.Type]...) -> [any Rule.Type] { rules.flatMap { $0 } }
    public static func buildArray(_ rules: [[any Rule.Type]]) -> [any Rule.Type] { rules.flatMap { $0 } }
    public static func buildOptional(_ rules: [any Rule.Type]?) -> [any Rule.Type] { rules ?? [] }
    public static func buildEither(first rules: [any Rule.Type]) -> [any Rule.Type] { rules }
    public static func buildEither(second rules: [any Rule.Type]) -> [any Rule.Type] { rules }
}
