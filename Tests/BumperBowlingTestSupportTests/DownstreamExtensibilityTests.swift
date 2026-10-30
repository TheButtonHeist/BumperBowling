import Foundation
import SwiftSyntax
import Testing
import BumperBowlingCore
import BumperBowlingTestSupport

/// A downstream fixture: everything here uses only public API, no
/// `@testable import`, no checkout, no Bumper source edits.
@Suite("Downstream extensibility")
struct DownstreamExtensibilityTests {
    @Test
    func downstreamVisitorRuleRunsAloneWithStructuredEvidence() throws {
        let rule = VisitorRule(
            metadata: RuleMetadata(
                id: "project.no_force_unwrap",
                severity: .error,
                summary: "Production code never force-unwraps."
            ),
            scope: .productionSources
        ) { file in
            ForceUnwrapVisitor(file: file)
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/App/Feature.swift",
                    component: "app",
                    source: "func f(value: Int?) -> Int { value! }"
                )
                VirtualSourceFile.swift(
                    "Tests/AppTests/FeatureTests.swift",
                    component: "app",
                    source: "func t(value: Int?) -> Int { value! }"
                )
            }
        )

        let violation = try #require(report.violations.first)
        #expect(report.violations.count == 1)
        #expect(violation.rule.id == RuleID("project.no_force_unwrap"))
        #expect(violation.path.rawValue == "Sources/App/Feature.swift")
        #expect(violation.location != nil)
        #expect(violation.evidence == ViolationEvidence(observed: "value!", expectation: "no force unwrap"))
    }

    @Test
    func downstreamFactProvidersDeriveOnceAndCompose() throws {
        let rule = RepositoryRule(
            metadata: RuleMetadata(
                id: "project.view_naming",
                severity: .error,
                summary: "Views end in View."
            )
        ) { context in
            try context.facts(MisnamedViewProvider()).map { occurrence in
                RuleFailure(
                    path: occurrence.path,
                    location: occurrence.location,
                    message: "\(occurrence.symbol.name) looks like a view but is not named one."
                )
            }
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/App/GoodView.swift", component: "app", source: "struct GoodView {}")
                VirtualSourceFile.swift("Sources/App/BadScreen.swift", component: "app", source: "struct BadScreen {}")
            }
        )

        #expect(report.violations.map(\.message) == ["BadScreen looks like a view but is not named one."])
    }

    @Test
    func downstreamQueryExtensionComposesWithBuiltInQueries() throws {
        let rule = Rules.forbid(
            functions().asyncFunctions().within(.productionSources),
            id: "project.no_async",
            summary: "This layer stays synchronous."
        ) { match in
            "\(match.node.name.text) is async."
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/App/Sync.swift",
                    component: "app",
                    source: """
                    func plain() {}
                    func fetch() async {}
                    """
                )
            }
        )

        #expect(report.violations.map(\.message) == ["fetch is async."])
    }

    @Test
    func downstreamSyntaxScopesAndValueFactsArePublic() throws {
        let file = SourceFileContext(
            descriptor: SourceFileDescriptor(
                path: "Sources/App/Store.swift",
                component: try ComponentID("app")
            ),
            source: """
            typealias Handler = (@Sendable (Payload) -> Void)?

            struct Store {
                let onChange: Handler
            }
            """
        )

        let storeMembers = SyntaxScope.typeMembers.intersecting(.enclosed(in: "Store"))
        let onChange = try #require(
            variables().storedMembers().lexically(within: storeMembers).matches(in: file).first
        )
        #expect(onChange.node.bindings.first?.bumper.explicitTypeShape?.outerTypeName == "Handler")

        let alias = try #require(typeAliases().matches(in: file).first)
        #expect(alias.node.bumper.aliasedTypeShape.isFunction)
        #expect(alias.node.bumper.aliasedTypeShape.hasAttribute(matching: "Sendable"))
    }

    @Test
    func mutableStoredMembersKeepDeclarationBoundariesAndSourceEvidence() throws {
        let harness = RuleTestHarness(Rules.each(
            variables().storedMembers().filter(\.isMutableBinding),
            id: "project.mutable_members", summary: "Models do not declare mutable stored members."
        ) { variable in
            [variable.failure(
                message: "Mutable state in \(variable.lexicalContext.enclosingNominalNames.joined(separator: ".")).",
                evidence: ViolationEvidence(
                    observed: variable.bindingNames.joined(separator: ", "), expectation: "no mutable stored members"
                )
            )]
        })
        let passing = try harness.evaluate(VirtualRepository {
            VirtualSourceFile.swift("Sources/Model.swift", source: """
            var global = 0
            struct Model {
                let fixed = 0
                var computed: Int { fixed }
                var accessor: Int { get { fixed } set {} }
                func work() { var local = 0; local += 1 }
            }
            """)
        })
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate(VirtualRepository {
            VirtualSourceFile.swift("Sources/Model.swift", source: """
            var global = 0
            struct Model {
                var first = 0, second = 1
                var observed = 0 { willSet {} didSet {} }
                let fixed = 0
                var computed: Int { fixed }
                func work() { var local = 0; local += 1 }
            }
            """)
        })
        #expect(failing.violations.count == 2)
        for (line, names) in [(3, "first, second"), (4, "observed")] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "project.mutable_members", path: "Sources/Model.swift",
                location: SourcePosition(line: line, column: 5), message: .exact("Mutable state in Model."),
                observed: .exact(names), expectation: .exact("no mutable stored members")
            )).count == 1)
        }
    }

    @Test
    func downstreamRuleGroupsEnterOneRuleSet() throws {
        let rules = RuleSet {
            projectRules()
            Rules.forbid(functionCalls(), id: "extra", summary: "none") { _ in "call" }
        }

        #expect(rules.rules.map(\.metadata.id) == [
            RuleID("project.first"),
            RuleID("project.second"),
            RuleID("extra"),
        ])
    }

    @Test
    func harnessReturnsCanonicalReportForConsumption() throws {
        let rule = Rules.repository(
            "project.no_uikit",
            summary: "UIKit imports are forbidden in the downstream fixture."
        ) { context in
            try context.facts(BuiltInFacts.imports).occurrences
                .filter { $0.module.rawValue == "UIKit" }
                .map { occurrence in
                    RuleFailure(path: occurrence.path, message: "UIKit is not allowed here.")
                }
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/App/Screen.swift", component: "app", source: "import UIKit")
            }
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(RuleReport.self, from: encoded)
        #expect(decoded == report)
        #expect(decoded.violations.map(\.rule.id) == [RuleID("project.no_uikit")])
    }
}

private func projectRules() -> [any RuleDefinition] {
    RuleSet {
        Rules.repository(
            "project.first",
            summary: "First downstream rule used to verify grouped rule composition."
        ) { _ in [] }
        Rules.repository(
            "project.second",
            summary: "Second downstream rule used to verify grouped rule composition."
        ) { _ in [] }
    }.rules
}

// A downstream closure-backed provider: the normal low-boilerplate API.
private let viewLikeTypes = DerivedFact<[DeclarationOccurrence]>("project.view_like_types") { context in
    try context.facts(BuiltInFacts.declarations).occurrences.filter { occurrence in
        occurrence.kind == .struct
    }
}

// A downstream named provider depending on the closure-backed provider.
private struct MisnamedViewProvider: FactProvider {
    let id: FactProviderID = "project.misnamed_views"

    func derive(in context: FactDerivationContext) throws -> [DeclarationOccurrence] {
        try context.facts(viewLikeTypes).filter { occurrence in
            !occurrence.symbol.name.hasSuffix("View")
        }
    }
}

// A downstream query extension over a built-in query root.
private extension SyntaxQuery where Node == FunctionDeclSyntax {
    func asyncFunctions() -> Self {
        filter { match in
            match.node.signature.effectSpecifiers?.asyncSpecifier != nil
        }
    }
}

private final class ForceUnwrapVisitor: SyntaxVisitor, RuleFailureSource {
    private let file: SourceFileContext
    private(set) var failures: [RuleFailure] = []

    init(file: SourceFileContext) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        failures.append(
            file.failure(
                at: node,
                message: "Force unwrap is not allowed in production sources.",
                evidence: ViolationEvidence(observed: node.trimmedDescription, expectation: "no force unwrap")
            )
        )
        return .visitChildren
    }
}
