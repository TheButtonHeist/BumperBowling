import Foundation
import SwiftSyntax
import Testing
@testable import BumperBowlingCore
import BumperBowlingTestSupport

@Suite("Rule engine")
struct RuleEngineTests {
    @Test
    func ruleSetBuilderAcceptsEveryRuleForm() throws {
        let includeOptional = true
        let ruleSet = RuleSet {
            Rules.repository(
                "closure.repository",
                summary: "Exercises repository closure rule construction."
            ) { _ in [] }
            Rules.files(
                "closure.syntax",
                summary: "Exercises per-file closure rule construction."
            ) { _ in [] }
            SyntaxRule(
                metadata: RuleMetadata(id: "typed.syntax", severity: .error, summary: "typed")
            ) { _ in [] }
            Rules.forbid(
                functionCalls(),
                id: "query.rule",
                summary: "no calls"
            ) { _ in "call" }
            Rules.visitor(
                "visitor.rule",
                summary: "Exercises visitor-backed rule construction."
            ) { file in
                RecordingVisitor(file: file)
            }
            if includeOptional {
                Rules.repository(
                    "conditional.rule",
                    summary: "Exercises conditional rule-builder composition."
                ) { _ in [] }
            }
            projectRuleGroup()
        }

        #expect(ruleSet.rules.map(\.metadata.id) == [
            "closure.repository",
            "closure.syntax",
            "typed.syntax",
            "query.rule",
            "visitor.rule",
            "conditional.rule",
            "grouped.one",
            "grouped.two",
        ])
    }

    @Test
    func scopesComposeOverPathsAndComponents() throws {
        let core = try ComponentID("core")
        let cli = try ComponentID("cli")
        let coreFile = SourceFileDescriptor(path: RelativeFilePath("Sources/Core/A.swift"), component: core)
        let cliFile = SourceFileDescriptor(path: RelativeFilePath("Sources/CLI/B.swift"), component: cli)
        let testFile = SourceFileDescriptor(path: RelativeFilePath("Tests/CoreTests/C.swift"), component: core)

        let underSources = RuleScope.under(RelativePathPrefix("Sources"))
        #expect(underSources.includes(coreFile))
        #expect(!underSources.includes(testFile))

        let coreOnly = RuleScope.component(core)
        #expect(coreOnly.includes(coreFile))
        #expect(!coreOnly.includes(cliFile))

        let union = coreOnly.union(RuleScope.component(cli))
        #expect(union.includes(cliFile))

        let excluded = underSources.excluding(RuleScope.files([cliFile.path]))
        #expect(excluded.includes(coreFile))
        #expect(!excluded.includes(cliFile))

        #expect(RuleScope.productionSources.includes(coreFile))
        #expect(!RuleScope.productionSources.includes(testFile))

        #expect(RuleScope.component(EngineTestComponent.core).includes(coreFile))
        #expect(!RuleScope.component(EngineTestComponent.core).includes(cliFile))
    }

    @Test
    func declarationAndMacroQueriesComposeWithProjectSpellings() throws {
        let file = SourceFileContext(
            descriptor: SourceFileDescriptor(
                path: RelativeFilePath("Sources/Features/CheckoutView.swift"),
                component: try ComponentID("features")
            ),
            source: """
            struct CheckoutView: View {}
            struct CheckoutState: Equatable {}
            #Preview("Checkout") { CheckoutView() }
            """
        )

        let views = structs()
            .inheriting("View")
            .matches(in: file)
        let previews = macroExpansions()
            .named("Preview")
            .matches(in: file)

        #expect(views.map { $0.node.name.text } == ["CheckoutView"])
        #expect(previews.count == 1)
    }

    @Test
    func invalidScopePathsFailAtConstruction() {
        // Runtime String values take the throwing initializers; only literals
        // get the trapping literal conversion.
        let traversalPrefix = "../outside"
        let absolutePath = "/absolute/path.swift"
        #expect(throws: ConfigurationError.self) {
            _ = try RelativePathPrefix(traversalPrefix)
        }
        #expect(throws: ConfigurationError.self) {
            _ = try RelativeFilePath(absolutePath)
        }
    }

    @Test
    func violationsRetainMetadataLocationAndEvidence() throws {
        let rule = SyntaxRule(
            metadata: RuleMetadata(id: "no.tuples", severity: .warning, summary: "No tuple APIs.")
        ) { file in
            SyntaxQuery<TupleTypeSyntax>().matches(in: file).map { match in
                match.failure(
                    message: "Tuple type found.",
                    evidence: ViolationEvidence(observed: match.node.trimmedDescription, expectation: "named type")
                )
            }
        }

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift(
                    "Sources/Core/Thing.swift",
                    component: "core",
                    source: "func pair() -> (String, Int) { (\"id\", 1) }"
                ),
            ]
        )

        let violation = try #require(report.violations.first)
        #expect(violation.rule == RuleMetadata(id: "no.tuples", severity: .warning, summary: "No tuple APIs."))
        #expect(violation.path.rawValue == "Sources/Core/Thing.swift")
        #expect(violation.location == SourcePosition(line: 1, column: 16))
        #expect(violation.evidence?.observed == "(String, Int)")
        #expect(!report.hasErrors)
    }

    @Test
    func reportsSortDeterministically() throws {
        let failures = [
            ("Sources/B.swift", 2, "z_rule"),
            ("Sources/A.swift", 9, "m_rule"),
            ("Sources/A.swift", 1, "m_rule"),
        ]
        let rules = RuleSet {
            for (index, failure) in failures.enumerated() {
                Rules.repository(
                    failure.2 + "_\(index)",
                    summary: "Emits a positioned failure to verify deterministic report ordering."
                ) { _ in
                    [
                        RuleFailure(
                            path: RuleEngineTests.path(failure.0),
                            location: SourcePosition(line: failure.1, column: 1),
                            message: "violation"
                        ),
                    ]
                }
            }
        }

        let context = RuleContext(
            configuration: ArchitectureConfiguration(components: []),
            repository: RepositorySyntax(files: [])
        )
        let report = try rules.evaluate(in: context)
        #expect(report.violations.map { "\($0.path.rawValue):\($0.location?.line ?? 0)" } == [
            "Sources/A.swift:1",
            "Sources/A.swift:9",
            "Sources/B.swift:2",
        ])
    }

    @Test
    func duplicateRuleIDsAreConfigurationErrors() throws {
        let rules = RuleSet {
            Rules.repository(
                "dup.rule",
                summary: "First declaration used to verify duplicate rule IDs are rejected."
            ) { _ in [] }
            Rules.repository(
                "dup.rule",
                summary: "Second declaration used to verify duplicate rule IDs are rejected."
            ) { _ in [] }
        }

        #expect(throws: RuleEvaluationError.duplicateRuleID(RuleID("dup.rule"))) {
            _ = try RuleTestHarness(rules).evaluate(
                [
                    SourceInput.swift("Sources/Core/A.swift", component: "core", source: "struct A {}"),
                ]
            )
        }
    }

    @Test
    func analysisFailuresAreExplicitErrors() throws {
        struct Underlying: Error {}
        let rules = RuleSet {
            Rules.files(
                "fine.rule",
                summary: "Provides a successful file rule before a failing evaluator."
            ) { _ in [] }
            SyntaxRule(
                metadata: RuleMetadata(id: "broken.rule", severity: .error, summary: "broken")
            ) { _ in
                throw Underlying()
            }
        }
        let harness = RuleTestHarness(rules.rules[1])

        #expect(throws: RuleEvaluationError.self) {
            _ = try harness.evaluate(
                [
                    SourceInput.swift("Sources/Core/A.swift", component: "core", source: "struct A {}"),
                ]
            )
        }
    }

    @Test
    func visitorRulesWalkOnlyScopedFiles() throws {
        let rule = VisitorRule(
            metadata: RuleMetadata(id: "visitor.structs", severity: .error, summary: "No structs."),
            scope: .under(RelativePathPrefix("Sources/Scoped"))
        ) { file in
            StructRecordingVisitor(file: file)
        }

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift("Sources/Scoped/In.swift", component: "core", source: "struct InScope {}"),
                SourceInput.swift("Sources/Other/Out.swift", component: "core", source: "struct OutOfScope {}"),
            ]
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Scoped/In.swift"])
    }

    @Test
    func queriesPreserveNodeTypesThroughComposition() throws {
        let file = SourceFileContext(
            descriptor: SourceFileDescriptor(
                path: RuleEngineTests.path("Sources/Core/Q.swift"),
                component: try ComponentID("core")
            ),
            source: """
            typealias Alias = Target
            func takesTarget(value: Target) {}
            func other(value: Int) {}
            func recurse(value: Target) { recurse(value: value) }
            """
        )

        let allFunctions = functions().matches(in: file)
        #expect(allFunctions.count == 3)

        let takingTarget = functions().taking(NominalSymbol("Target")).matches(in: file)
        #expect(takingTarget.map(\.node.name.text) == ["takesTarget", "recurse"])

        let recursive = functions().callingSelf().matches(in: file)
        #expect(recursive.map(\.node.name.text) == ["recurse"])

        let aliases = typeAliases().aliasing(NominalSymbol("Target")).matches(in: file)
        #expect(aliases.map(\.node.name.text) == ["Alias"])

        // map preserves the transformed node type: FunctionDeclSyntax -> TokenSyntax.
        let names: [SyntaxMatch<TokenSyntax>] = functions()
            .compactMap { match in match.node.name }
            .matches(in: file)
        #expect(names.map(\.node.text) == ["takesTarget", "other", "recurse"])
    }

    @Test
    func factProvidersMemoizeAndSupportDependencies() throws {
        CountingProvider.derivations.reset()
        let rule = Rules.repository(
            "facts.rule",
            summary: "Exercises rule construction alongside fact-provider memoization."
        ) { _ in [] }
        let context = try makeContext(
            source: "struct Counted {}",
            path: "Sources/Core/Counted.swift"
        )
        _ = rule

        let first = try context.facts(CountingProvider())
        let second = try context.facts(CountingProvider())
        let dependent = try context.facts(DependentProvider())

        #expect(first == 1)
        #expect(second == 1)
        #expect(dependent == "declarations: 1, base: 1")
        #expect(CountingProvider.derivations.value == 1)
    }

    @Test
    func factProviderCyclesAreExplicitErrors() throws {
        let context = try makeContext(
            source: "struct A {}",
            path: "Sources/Core/A.swift"
        )

        #expect(throws: FactProviderError.self) {
            _ = try context.facts(CycleAProvider())
        }
    }

    private func makeContext(source: String, path: String) throws -> RuleContext {
        RuleContext(
            configuration: ArchitectureConfiguration(components: []),
            repository: RepositorySyntax(files: [
                SourceFileContext(
                    descriptor: SourceFileDescriptor(
                        path: try RelativeFilePath(path),
                        component: try ComponentID("core")
                    ),
                    source: source
                ),
            ])
        )
    }

    private static func path(_ value: String) -> RelativeFilePath {
        guard let path = try? RelativeFilePath(value) else {
            preconditionFailure("Invalid test path: \(value)")
        }
        return path
    }
}

private enum EngineTestComponent: String, ComponentKey {
    case core
    case cli
}

private func projectRuleGroup() -> [any RuleDefinition] {
    RuleSet {
        Rules.repository(
            "grouped.one",
            summary: "First rule in a reusable rule group."
        ) { _ in [] }
        Rules.repository(
            "grouped.two",
            summary: "Second rule in a reusable rule group."
        ) { _ in [] }
    }.rules
}

private final class RecordingVisitor: SyntaxVisitor, RuleFailureSource {
    private(set) var failures: [RuleFailure] = []

    init(file: SourceFileContext) {
        super.init(viewMode: .sourceAccurate)
        _ = file
    }
}

private final class StructRecordingVisitor: SyntaxVisitor, RuleFailureSource {
    private let file: SourceFileContext
    private(set) var failures: [RuleFailure] = []

    init(file: SourceFileContext) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        failures.append(file.failure(at: node, message: "Struct \(node.name.text) found."))
        return .visitChildren
    }
}

final class DerivationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        count = 0
    }
}

private struct CountingProvider: FactProvider {
    let id: FactProviderID = "test.counting"
    static let derivations = DerivationCounter()

    func derive(in context: FactDerivationContext) throws -> Int {
        Self.derivations.increment()
    }
}

private struct DependentProvider: FactProvider {
    let id: FactProviderID = "test.dependent"

    func derive(in context: FactDerivationContext) throws -> String {
        let declarations = try context.facts(BuiltInFacts.declarations)
        let base = try context.facts(CountingProvider())
        return "declarations: \(declarations.occurrences.count), base: \(base)"
    }
}

private struct CycleAProvider: FactProvider {
    let id: FactProviderID = "test.cycle_a"

    func derive(in context: FactDerivationContext) throws -> Int {
        try context.facts(CycleBProvider())
    }
}

private struct CycleBProvider: FactProvider {
    let id: FactProviderID = "test.cycle_b"

    func derive(in context: FactDerivationContext) throws -> Int {
        try context.facts(CycleAProvider())
    }
}
