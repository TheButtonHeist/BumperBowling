import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

private enum AppComponent: String, ComponentKey {
    case core
}

@Suite("Spec authoring spellings")
struct SpecSpellingTests {
    @Test
    func derivedFactAndClosureRulesAcceptSpecSpellings() throws {
        let uikitImports = DerivedFact<[ImportOccurrence]>("app.uikit_imports") { context in
            try context.facts(BuiltInFacts.imports).occurrences
                .filter { occurrence in occurrence.module.rawValue == "UIKit" }
        }

        let rule = Rules.repository(
            "app.import_allow_list",
            severity: .error,
            summary: "UIKit imports are forbidden in the core component.",
            scope: .component(AppComponent.core)
        ) { subjects, context in
            let paths = Set(subjects.map(\.path))
            return try context.facts(uikitImports).filter { paths.contains($0.path) }.map { occurrence in
                RuleFailure(path: occurrence.path, message: "UIKit is not allowed here.")
            }
        }

        let report = try RuleTestHarness(rule).evaluate(
            [
                .init(
                    path: "Sources/Core/Screen.swift",
                    component: try ComponentID(AppComponent.core.rawValue),
                    source: "import UIKit"
                ),
            ]
        )

        #expect(report.violations.map(\.rule.id) == ["app.import_allow_list"])
    }

    @Test
    func harnessAndMatchersAcceptSpecSpellings() throws {
        let recursiveSource = """
        func walk(tree: SyntaxTree) {
            if case .container = tree {
                walk(tree: tree)
            }
        }
        """

        let canonicalTreeTraversal = Rules.canonicalTraversal(
            root: "SyntaxTree",
            structuralCase: "container",
            owners: .under("Sources/Traversal"),
            id: "app.canonical_tree"
        )

        let report = try RuleTestHarness(canonicalTreeTraversal).evaluate(
            [
                .init(
                    path: "Sources/Invalid.swift",
                    component: try ComponentID(AppComponent.core.rawValue),
                    source: recursiveSource
                ),
            ]
        )

        #expect(report.violations.map(\.rule.id) == ["app.canonical_tree"])
        #expect(
            report.contains(
                ViolationMatcher(
                    id: "app.canonical_tree",
                    path: "Sources/Invalid.swift",
                    message: .contains("recursively traverses"),
                    observed: .contains("SyntaxTree")
                )
            )
        )
    }

    @Test
    func regexMatchingIsExplicit() throws {
        let matcher = StringMatcher.regex("^legacy[A-Z]")

        #expect(matcher.matches("legacyThing"))
        #expect(!matcher.matches("modernThing"))
        #expect(StringMatcher("legacyThing") == .exact("legacyThing"))
    }
}
