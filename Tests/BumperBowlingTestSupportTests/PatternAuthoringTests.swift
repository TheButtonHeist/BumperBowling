import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftSyntax
import Testing

@Suite("Public pattern authoring")
struct PatternAuthoringTests {
    @Test(arguments: [SyntaxCounting.perFile, .repository])
    func matchCountSeparatesSelectionFromAggregation(counting: SyntaxCounting) throws {
        let pattern = structs().filter { $0.node.name.text.hasSuffix("Adapter") }
        let harness = RuleTestHarness(Rules.assert(
            pattern, cardinality: .exactly(1), counting: counting,
            id: "adapters.one", summary: "One adapter struct per counting unit."
        ))
        let first = SourceInput.swift("Sources/A.swift", component: "app", source: "struct AppAdapter {}")
        let second = SourceInput.swift("Sources/B.swift", component: "app", source: "struct TestAdapter {}")
        let empty = SourceInput.swift("Sources/B.swift", component: "app", source: "struct B {}")
        let passing = try harness.evaluate([first, counting == .perFile ? second : empty])
        #expect(passing.violations.isEmpty)

        let failingFiles: [SourceInput] = counting == .perFile
            ? [.swift("Sources/A.swift", component: "app", source: "struct AppAdapter {}\nstruct ExtraAdapter {}"), empty]
            : [first, second]
        let failing = try harness.evaluate(failingFiles)
        let reversed = try harness.evaluate(Array(failingFiles.reversed()))
        #expect(failing.violations == reversed.violations)
        if counting == .perFile {
            let defaultHarness = RuleTestHarness(Rules.assert(pattern, cardinality: .exactly(1), id: "adapters.one", summary: "One adapter struct per counting unit."))
            #expect(try defaultHarness.evaluate([first, second]).violations.isEmpty)
            #expect(try defaultHarness.evaluate(failingFiles).violations == failing.violations)
            #expect(failing.violations.count == 2)
            #expect(failing.contains(ViolationMatcher(
                id: "adapters.one", path: "Sources/A.swift", location: SourcePosition(line: 2, column: 1),
                observed: .exact("2 matching syntax nodes")
            )))
            let missing = try #require(failing.violations.first { $0.path.rawValue == "Sources/B.swift" })
            #expect(missing.location == nil)
            #expect(missing.evidence?.observed == "0 matching syntax nodes")
        } else {
            #expect(failing.violations.count == 1)
            #expect(failing.contains(ViolationMatcher(
                id: "adapters.one", path: "Sources/B.swift", location: SourcePosition(line: 1, column: 1),
                observed: .exact("2 matching syntax nodes"), expectation: .exact("exactly 1 matching syntax node")
            )))
        }
    }

    @Test func repositoryShortageHasStableFileEvidenceAndRespectsScope() throws {
        let harness = RuleTestHarness(Rules.assert(
            typeAliases(), cardinality: .atLeast(2), counting: .repository,
            id: "aliases.minimum", scope: .under("Sources")
        ) { violation in
            "\(violation.counting): found \(violation.observedCount)."
        })
        let first = SourceInput.swift("Sources/A.swift", component: "app", source: "typealias A = Int")
        let second = SourceInput.swift("Sources/B.swift", component: "app", source: "typealias B = Int")
        #expect(try harness.evaluate([first, second]).violations.isEmpty)
        let files: [SourceInput] = [
            .swift("Sources/A.swift", component: "app", source: "struct A {}"), second,
            .swift("Tests/Extra.swift", component: "app", source: "typealias Extra = Int"),
        ]
        let failing = try harness.evaluate(files)
        #expect(failing.violations == (try harness.evaluate(Array(files.reversed()))).violations)
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "aliases.minimum", path: "Sources/A.swift", message: .exact("repository: found 1."),
            observed: .exact("1 matching syntax node"), expectation: .exact("at least 2 matching syntax nodes")
        )))
        #expect(failing.violations.first?.location == nil)
    }

    @Test(arguments: [SyntaxCardinality.none, .atMost(1)])
    func repositoryExcessMatchesKeepTheirOwnFiles(cardinality: SyntaxCardinality) throws {
        let harness = RuleTestHarness(Rules.assert(
            typeAliases(), cardinality: cardinality, counting: .repository, id: "aliases.maximum"
        ))
        let empty = SourceInput.swift("Sources/Empty.swift", component: "app", source: "struct Empty {}")
        #expect(try harness.evaluate([empty]).violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/A.swift", component: "app", source: "typealias A = Int"),
            SourceInput.swift("Sources/B.swift", component: "app", source: "typealias B = Int\ntypealias C = Int"),
        ])
        #expect(failing.violations.count == (cardinality == .none ? 3 : 2))
        for line in [1, 2] {
            #expect(failing.contains(ViolationMatcher(
                id: "aliases.maximum", path: "Sources/B.swift", location: SourcePosition(line: line, column: 1),
                observed: .exact("3 matching syntax nodes"), expectation: .exact(cardinality.description)
            )))
        }
    }

    @Test(arguments: [SyntaxCounting.perFile, .repository])
    func positiveRequirementsRejectEmptyScopes(counting: SyntaxCounting) throws {
        let harness = RuleTestHarness(Rules.assert(
            structs(), cardinality: .atLeast(1), counting: counting,
            id: "scope.required", scope: .under("Sources/Core")
        ))
        #expect(try harness.evaluate([
            SourceInput.swift("Sources/Core/Model.swift", component: "core", source: "struct Model {}"),
        ]).violations.isEmpty)
        #expect(throws: RuleEvaluationError.emptyRuleScope("scope.required")) {
            try harness.evaluate([
                SourceInput.swift("Sources/Other/Model.swift", component: "other", source: "struct Model {}"),
            ])
        }
    }

    @Test(arguments: [SyntaxCardinality.none, .atLeast(0), .atMost(0), .exactly(0)])
    func zeroRequirementsPermitEmptyRepositories(cardinality: SyntaxCardinality) throws {
        for counting in [SyntaxCounting.perFile, .repository] {
            let harness = RuleTestHarness(Rules.assert(structs(), cardinality: cardinality, counting: counting, id: "scope.zero"))
            #expect(try harness.evaluate([]).violations.isEmpty)
        }
    }

    @Test(arguments: [SyntaxCardinality.atLeast(-1), .atMost(-1), .exactly(-1)])
    func negativeCardinalitiesFailExplicitly(cardinality: SyntaxCardinality) throws {
        let harness = RuleTestHarness(Rules.assert(structs(), cardinality: cardinality, id: "count.invalid"))
        #expect(throws: RuleEvaluationError.invalidSyntaxCardinality("count.invalid", -1)) {
            try harness.evaluate([])
        }
    }

    @Test func eachPropagatesAnalysisErrorsAndHonorsScope() throws {
        let harness = RuleTestHarness(Rules.each(
            structs(), id: "each.analysis", summary: "Analysis errors remain explicit.", scope: .under("Sources/Core")
        ) { match in
            if match.node.name.text == "Broken" { throw RecipeError.incomplete }
            return []
        })
        #expect(try harness.evaluate([
            SourceInput.swift("Sources/Core/Good.swift", component: "core", source: "struct Good {}"),
            SourceInput.swift("Sources/Other/Broken.swift", component: "other", source: "struct Broken {}"),
        ]).violations.isEmpty)
        #expect(throws: RuleEvaluationError.ruleFailed("each.analysis", "incomplete")) {
            try harness.evaluate([
                SourceInput.swift("Sources/Core/Broken.swift", component: "core", source: "struct Broken {}"),
            ])
        }
    }
}

private enum RecipeError: Error { case incomplete }
