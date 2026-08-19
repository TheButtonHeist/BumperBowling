import Foundation
import Testing
import BumperBowlingCore
import BumperBowlingTestSupport

@Suite("Standard architectural shapers")
struct StandardShaperTests {
    @Test
    func importOwnershipFlagsImportsOutsideOwners() throws {
        let rule = Rules.importOwnership(
            ["UIKit", "Network"],
            allowed: .component(try ComponentID("boundary"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Boundary/Adapter.swift",
                    component: "boundary",
                    source: "import UIKit"
                )
                VirtualSourceFile.swift(
                    "Sources/Core/Feature.swift",
                    component: "core",
                    source: "import Network\nimport Foundation"
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Core/Feature.swift"])
        #expect(report.violations.first?.evidence?.observed == "import Network in Sources/Core/Feature.swift")
    }

    @Test
    func memberReferenceOwnershipFlagsReferencesOutsideOwners() throws {
        let rule = Rules.memberReferenceOwnership(
            .prefix("unsafe"),
            allowed: .under("Sources/Boundary")
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Boundary/Adapter.swift",
                    component: "boundary",
                    source: "func bridge(_ value: Resource) { _ = value.unsafeHandle }"
                )
                VirtualSourceFile.swift(
                    "Sources/Core/Feature.swift",
                    component: "core",
                    source: "func leak(_ value: Resource) { _ = value.unsafeHandle }"
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Core/Feature.swift"])
        #expect(report.violations.first?.evidence?.observed == "value.unsafeHandle")
    }

    @Test
    func memberReferenceOwnershipSupportsMultipleMatchersUnderOneRuleID() throws {
        let report = try RuleTestHarness(
            Rules.memberReferenceOwnership(["observe", "stop"], allowed: .under("Sources/Owner"), id: "lifecycle")
        ).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Elsewhere/Leak.swift", component: "core", source: "func leak(_ value: API) { value.observe(); value.stop() }")
            }
        )

        #expect(report.violations.map(\.ruleID) == ["lifecycle", "lifecycle"])
        #expect(report.violations.map(\.evidence?.observed) == ["value.observe", "value.stop"])
    }

    @Test
    func declarationAndAccessShapersCoverInternalFunctionsAndSPI() throws {
        let ownership = Rules.declarationOwnership([.suffix("Receipt")], allowed: .under("Sources/Owner"), id: "receipt_owner")
        let publicAPI = Rules.publicAPIOwnership(allowed: .under("Sources/API"), id: "public_owner")
        let spi = Rules.spiOwnership(allowed: .under("Sources/Bridge"), id: "spi_owner")
        let report = try RuleTestHarness(RuleSet { ownership; publicAPI; spi }).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Elsewhere/Leak.swift", component: "core", source: "struct ResultReceipt {}\npublic func leaked() {}\n@_spi(Bridge) func bridge() {}")
            }
        )

        #expect(report.violations.map(\.ruleID) == ["receipt_owner", "public_owner", "spi_owner"])
    }

    @Test
    func typeAndStoredPropertyShapersCoverNewFactSurfaces() throws {
        let types = Rules.disallowTypeReferences("Any", in: .repository, id: "no_any")
        let bools = Rules.maximumStoredProperties(matching: "Bool", maximum: 1, in: .repository, id: "bool_soup")
        let report = try RuleTestHarness(RuleSet { types; bools }).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Core/State.swift", component: "core", source: "struct State { let one: Bool; let two: Bool }\nfunc leak(_ value: Any) -> Any { value }")
            }
        )

        #expect(report.violations.map(\.ruleID) == ["bool_soup", "bool_soup", "no_any", "no_any"])
    }

    @Test
    func stateMachineShapeRequiresAssociatedValueCasesWhenConfigured() throws {
        let report = try RuleTestHarness(
            Rules.stateMachineShape(in: .repository, requiresAssociatedValueCase: true)
        ).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Core/State.swift", component: "core", source: "enum WorkflowState { case idle }")
            }
        )

        #expect(report.violations.first?.message == "State enum has no associated-value case.")
    }

    @Test
    func singleDeclarationPassesForOneOwnedDeclaration() throws {
        let rule = Rules.singleDeclaration(
            NominalSymbol("AccessibilityTarget"),
            owner: RelativePathPrefix("Sources/Plans")
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
            }
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func singleDeclarationFlagsDuplicatesAndForeignOwners() throws {
        let rule = Rules.singleDeclaration(
            NominalSymbol("AccessibilityTarget"),
            owner: RelativePathPrefix("Sources/Plans")
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
                VirtualSourceFile.swift("Sources/Plans/Duplicate.swift", component: "plans", source: "struct AccessibilityTarget {}")
                VirtualSourceFile.swift("Sources/Score/Foreign.swift", component: "score", source: "struct AccessibilityTarget {}")
            }
        )

        #expect(report.violations.count == 2)
        #expect(report.violations.map(\.path.rawValue).sorted() == [
            "Sources/Plans/Duplicate.swift",
            "Sources/Score/Foreign.swift",
        ])
    }

    @Test
    func singleDeclarationMissingOwnerFilesIsConfigurationFailure() throws {
        let rule = Rules.singleDeclaration(
            NominalSymbol("AccessibilityTarget"),
            owner: RelativePathPrefix("Sources/Missing")
        )

        #expect(throws: RuleEvaluationError.self) {
            _ = try RuleTestHarness(rule).evaluate(
                VirtualRepository {
                    VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
                }
            )
        }
    }

    @Test
    func constructionOwnershipFlagsOutsideBuilders() throws {
        let rule = Rules.constructionOwnership(
            NominalSymbol("InterfaceObservation"),
            allowed: .under(RelativePathPrefix("Sources/Builders"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Builders/Builder.swift",
                    component: "core",
                    source: "func make() { _ = InterfaceObservation() }"
                )
                VirtualSourceFile.swift(
                    "Sources/Feature/Rogue.swift",
                    component: "core",
                    source: "func rogue() { _ = InterfaceObservation() }"
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Rogue.swift"])
        #expect(report.violations.first?.rule.id == "construction_ownership")
    }

    @Test
    func boundaryOnlyFlagsCallsOutsideBoundary() throws {
        let rule = Rules.boundaryOnly(
            function: FunctionSymbol("JSONDecoder.decode"),
            allowed: .under(RelativePathPrefix("Sources/Boundary"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Boundary/Gate.swift",
                    component: "core",
                    source: "func load(data: Data) throws { _ = try JSONDecoder().decode(Thing.self, from: data) }"
                )
                VirtualSourceFile.swift(
                    "Sources/Feature/Leak.swift",
                    component: "core",
                    source: "func leak(data: Data) throws { _ = try JSONDecoder().decode(Thing.self, from: data) }"
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Leak.swift"])
    }

    @Test
    func noAlternateAliasesFlagsAliasesOutsideFacade() throws {
        let rule = Rules.noAlternateAliases(
            NominalSymbol("AccessibilityTarget"),
            allowing: .under(RelativePathPrefix("Sources/DSL"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/DSL/Facade.swift", component: "core", source: "typealias Target = AccessibilityTarget")
                VirtualSourceFile.swift("Sources/Feature/Alias.swift", component: "core", source: "typealias MyTarget = AccessibilityTarget")
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Alias.swift"])
        #expect(report.violations.first?.message.contains("MyTarget") == true)
    }

    @Test
    func canonicalTraversalFlagsRecursionOutsideOwners() throws {
        let recursiveSource = """
        func walk(hierarchy: AccessibilityHierarchy) {
            if case .container = hierarchy {
                walk(hierarchy: hierarchy)
            }
        }
        """
        let rule = Rules.canonicalTraversal(
            root: NominalSymbol("AccessibilityHierarchy"),
            structuralCase: EnumCaseSymbol("container"),
            owners: .under(RelativePathPrefix("Sources/Traversal")),
            id: "canonical_hierarchy_traversal"
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Traversal/Owner.swift", component: "score", source: recursiveSource)
                VirtualSourceFile.swift("Sources/Score/Invalid.swift", component: "score", source: recursiveSource)
            }
        )

        #expect(report.violations.map(\.rule.id) == ["canonical_hierarchy_traversal"])
        #expect(report.violations.map(\.path.rawValue) == ["Sources/Score/Invalid.swift"])
        #expect(report.violations.first?.evidence?.observed.contains(".container") == true)
    }

    @Test
    func canonicalTraversalRequiresTheConfiguredStructuralCase() throws {
        let source = """
        func visit(tree: Tree) {
            if case .branch = tree {
                visit(tree: tree)
            }
        }
        """
        let branchRule = Rules.canonicalTraversal(
            root: "Tree",
            structuralCase: "branch",
            owners: .under("Sources/Traversal")
        )
        let leafRule = Rules.canonicalTraversal(
            root: "Tree",
            structuralCase: "leaf",
            owners: .under("Sources/Traversal")
        )
        let repository = VirtualRepository {
            VirtualSourceFile.swift("Sources/Feature/Walk.swift", component: "core", source: source)
        }

        let branchReport = try RuleTestHarness(branchRule).evaluate(repository)
        let leafReport = try RuleTestHarness(leafRule).evaluate(repository)

        #expect(branchReport.violations.count == 1)
        #expect(leafReport.violations.isEmpty)
    }

    @Test
    func canonicalTraversalRequiresTheCasePatternToMatchTheRootParameter() throws {
        let rule = Rules.canonicalTraversal(
            root: "Tree",
            structuralCase: "branch",
            owners: .under("Sources/Traversal")
        )
        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Feature/WrongSubject.swift",
                    component: "core",
                    source: """
                    func visit(tree: Tree, marker: Marker) {
                        if case .branch = marker {
                            visit(tree: tree, marker: marker)
                        }
                    }
                    """
                )
            }
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func canonicalTraversalAcceptsSelfAsTheRootMethodSubject() throws {
        let rule = Rules.canonicalTraversal(
            root: "Tree",
            structuralCase: "branch",
            owners: .under("Sources/Traversal")
        )
        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Feature/Tree.swift",
                    component: "core",
                    source: """
                    enum Tree {
                        case branch

                        func visit() {
                            if case .branch = self {
                                visit()
                            }
                        }
                    }
                    """
                )
            }
        )

        #expect(report.violations.count == 1)
        #expect(report.violations.first?.evidence?.observed.contains("against self") == true)
    }

    @Test
    func canonicalTraversalIgnoresRootRecursionWithoutStructuralCaseEvidence() throws {
        let rule = Rules.canonicalTraversal(
            root: "Tree",
            structuralCase: "branch",
            owners: .under("Sources/Traversal")
        )
        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Feature/Unstructured.swift",
                    component: "core",
                    source: """
                    func visit(tree: Tree) {
                        let unrelated = Marker.branch
                        visit(tree: tree)
                    }
                    """
                )
            }
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func canonicalTraversalFlagsMutualRecursionOutsideOwners() throws {
        let rule = Rules.canonicalTraversal(
            root: NominalSymbol("AccessibilityHierarchy"),
            structuralCase: EnumCaseSymbol("container"),
            owners: .under(RelativePathPrefix("Sources/Traversal"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Score/Mutual.swift",
                    component: "score",
                    source: """
                    func descend(hierarchy: AccessibilityHierarchy) {
                        visit(hierarchy: hierarchy)
                    }

                    func visit(hierarchy: AccessibilityHierarchy) {
                        if case .container = hierarchy {
                            descend(hierarchy: hierarchy)
                        }
                    }
                    """
                )
                VirtualSourceFile.swift(
                    "Sources/Score/OtherReceiver.swift",
                    component: "score",
                    source: """
                    struct Renderer {
                        let walker: Walker

                        func render(hierarchy: AccessibilityHierarchy) {
                            walker.render(hierarchy: hierarchy)
                        }
                    }
                    """
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == [
            "Sources/Score/Mutual.swift",
            "Sources/Score/Mutual.swift",
        ])
        #expect(Set(report.violations.compactMap { $0.message.split(separator: " ").first }) == ["descend", "visit"])
    }

    @Test
    func canonicalConstructionFlagsConstructionOutsideOwners() throws {
        let rule = Rules.canonicalConstruction(
            NominalSymbol("InterfaceGraph"),
            owners: .under(RelativePathPrefix("Sources/Builders"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Builders/Builder.swift",
                    component: "core",
                    source: "func make() { _ = InterfaceGraph() }"
                )
                VirtualSourceFile.swift(
                    "Sources/Feature/Rogue.swift",
                    component: "core",
                    source: "func rogue() { _ = InterfaceGraph() }"
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Rogue.swift"])
        #expect(report.violations.first?.rule.id == "canonical_construction")
    }

    @Test
    func singleNominalSpellingFlagsSuffixedDeclarationsOutsideOwner() throws {
        let rule = Rules.singleNominalSpelling(
            suffix: "Expr",
            owner: .under(RelativePathPrefix("Sources/Plans"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Plans/Exprs.swift", component: "plans", source: "enum LiteralExpr {}")
                VirtualSourceFile.swift("Sources/Score/Rogue.swift", component: "score", source: "struct CallExpr {}")
                VirtualSourceFile.swift("Sources/Score/Unrelated.swift", component: "score", source: "struct Scorecard {}")
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Score/Rogue.swift"])
        #expect(report.violations.first?.message.contains("CallExpr") == true)
    }
}
