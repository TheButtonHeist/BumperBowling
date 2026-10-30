import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

/// The exact authoring spellings from the open shaper architecture spec.
/// These fixtures compile against public imports only; if a signature drifts
/// from the spec's letter, this file stops building.
private enum AppComponent: String, ComponentKey {
    case core
    case plans
    case dsl
}

@Suite("Spec authoring spellings")
struct SpecSpellingTests {
    @Test
    func shaperFactoriesAcceptSpecSpellings() throws {
        let observationBuilderPaths: Set<RelativeFilePath> = ["Sources/Builders/Builder.swift"]
        let jsonBoundaryScope = RuleScope.under("Sources/Boundary")
        let hierarchyTraversalOwners = RuleScope.under("Sources/Traversal")
        let interfaceGraphBuilders = RuleScope.under("Sources/Builders")

        let rules = RuleSet {
            Rules.singleDeclaration(
                "AccessibilityTarget",
                owner: "Sources/ThePlans/AccessibilityTarget.swift"
            )
            Rules.constructionOwnership(
                "InterfaceObservation",
                allowed: .files(observationBuilderPaths)
            )
            Rules.boundaryOnly(
                function: "JSONDecoder.decode",
                allowed: jsonBoundaryScope
            )
            Rules.noAlternateAliases(
                "AccessibilityTarget",
                allowing: .component(AppComponent.dsl)
            )
            Rules.canonicalTraversal(
                root: "AccessibilityHierarchy",
                structuralCase: "container",
                owners: hierarchyTraversalOwners
            )
            Rules.canonicalConstruction(
                "InterfaceGraph",
                owners: interfaceGraphBuilders
            )
            Rules.singleNominalSpelling(
                suffix: "Expr",
                owner: .component(AppComponent.plans)
            )
            Rules.forbid(
                typeAliases().aliasing("AccessibilityTarget"),
                id: "app.no_target_aliases",
                severity: .error,
                message: { _ in "AccessibilityTarget must not have an alternate alias" }
            )
        }

        #expect(rules.rules.count == 8)
    }

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
        func walk(hierarchy: AccessibilityHierarchy) {
            if case .container = hierarchy {
                walk(hierarchy: hierarchy)
            }
        }
        """

        let canonicalHierarchyTraversal = Rules.canonicalTraversal(
            root: "AccessibilityHierarchy",
            structuralCase: "container",
            owners: .under("Sources/Traversal"),
            id: "app.canonical_hierarchy"
        )

        let report = try RuleTestHarness(canonicalHierarchyTraversal).evaluate(
            [
                .init(
                    path: "Sources/Invalid.swift",
                    component: try ComponentID(AppComponent.core.rawValue),
                    source: recursiveSource
                ),
            ]
        )

        #expect(report.violations.map(\.rule.id) == ["app.canonical_hierarchy"])
        #expect(
            report.contains(
                ViolationMatcher(
                    id: "app.canonical_hierarchy",
                    path: "Sources/Invalid.swift",
                    message: .contains("recursively traverses"),
                    observed: .contains("AccessibilityHierarchy")
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
