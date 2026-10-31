/// Combines independent checks. Every applicable check runs and keeps its own scope.
@resultBuilder
public enum CheckBuilder {
    public static func buildExpression(_ check: SyntaxCheck) -> SyntaxCheck { check }

    public static func buildBlock(_ checks: SyntaxCheck...) -> SyntaxCheck { combine(checks) }
    public static func buildArray(_ checks: [SyntaxCheck]) -> SyntaxCheck { combine(checks) }
    public static func buildOptional(_ check: SyntaxCheck?) -> SyntaxCheck { combine(check.map { [$0] } ?? []) }
    public static func buildEither(first check: SyntaxCheck) -> SyntaxCheck { check }
    public static func buildEither(second check: SyntaxCheck) -> SyntaxCheck { check }

    private static func combine(_ checks: [SyntaxCheck]) -> SyntaxCheck {
        SyntaxCheck(scope: .union(checks.map(\.scope))) { file in checks.flatMap { $0.check(file) } }
    }
}
