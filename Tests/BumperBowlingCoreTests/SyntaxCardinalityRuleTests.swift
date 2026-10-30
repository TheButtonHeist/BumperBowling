import SwiftSyntax
import Testing
@testable import BumperBowlingCore
import BumperBowlingTestSupport

@Suite("Syntax cardinality rules")
struct SyntaxCardinalityRuleTests {
    @Test
    func forbidsFunctionCallsWithNodeEvidence() throws {
        let rule = Rules.assert(
            functionCalls(),
            cardinality: .none,
            id: "syntax.no_function_calls",
            summary: "Functions do not call other functions."
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift(
                    "Sources/Core/Runner.swift",
                    component: "core",
                    source: "func run() { execute() }"
                ),
            ]
        )

        let violation = try #require(report.violations.first)
        #expect(violation.location != nil)
        #expect(violation.evidence?.observed == "1 matching syntax node")
        #expect(violation.evidence?.expectation == "no matching syntax nodes")
    }

    @Test
    func limitsVariableDeclarationsWithExcessNodeEvidence() throws {
        let rule = Rules.assert(
            SyntaxQuery<VariableDeclSyntax>(),
            cardinality: .atMost(1),
            id: "syntax.one_variable",
            summary: "Files declare at most one variable."
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift(
                    "Sources/Core/Model.swift",
                    component: "core",
                    source: "let first = 1\nlet second = 2"
                ),
            ]
        )

        let violation = try #require(report.violations.first)
        #expect(report.violations.count == 1)
        #expect(violation.location == SourcePosition(line: 2, column: 1))
        #expect(violation.evidence?.observed == "2 matching syntax nodes")
        #expect(violation.evidence?.expectation == "at most 1 matching syntax node")
    }

    @Test
    func requiresEnumDeclarationsWithinScopeWithFileEvidence() throws {
        let rule = Rules.assert(
            SyntaxQuery<EnumDeclSyntax>(),
            cardinality: .atLeast(1),
            id: "syntax.domain_enum",
            summary: "Every domain file declares an enum.",
            scope: .under("Sources/Domain")
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift(
                    "Sources/Domain/Model.swift",
                    component: "domain",
                    source: "struct Model {}"
                ),
                SourceInput.swift(
                    "Sources/UI/View.swift",
                    component: "ui",
                    source: "enum ViewState { case idle }"
                ),
            ]
        )

        let violation = try #require(report.violations.first)
        #expect(report.violations.count == 1)
        #expect(violation.path.rawValue == "Sources/Domain/Model.swift")
        #expect(violation.location == nil)
        #expect(violation.evidence?.observed == "0 matching syntax nodes")
        #expect(violation.evidence?.expectation == "at least 1 matching syntax node")
    }

    @Test
    func requiresAnExactNumberOfTypeAliases() throws {
        let rule = Rules.assert(
            typeAliases(),
            cardinality: .exactly(1),
            id: "syntax.one_type_alias",
            summary: "Files declare exactly one type alias."
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift(
                    "Sources/Core/Types.swift",
                    component: "core",
                    source: "struct Identifier {}"
                ),
            ]
        )

        let violation = try #require(report.violations.first)
        #expect(violation.location == nil)
        #expect(violation.evidence?.observed == "0 matching syntax nodes")
        #expect(violation.evidence?.expectation == "exactly 1 matching syntax node")
    }
}
