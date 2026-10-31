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
            [
                SourceInput.swift(
                    "Sources/Boundary/Adapter.swift",
                    component: "boundary",
                    source: "import UIKit"
                ),
                SourceInput.swift(
                    "Sources/Core/Feature.swift",
                    component: "core",
                    source: "import Network\nimport Foundation"
                ),
            ]
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
            [
                SourceInput.swift(
                    "Sources/Boundary/Adapter.swift",
                    component: "boundary",
                    source: "func bridge(_ value: Resource) { _ = value.unsafeHandle }"
                ),
                SourceInput.swift(
                    "Sources/Core/Feature.swift",
                    component: "core",
                    source: "func leak(_ value: Resource) { _ = value.unsafeHandle }"
                ),
            ]
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Core/Feature.swift"])
        #expect(report.violations.first?.evidence?.observed == "value.unsafeHandle")
    }

    @Test
    func memberReferenceOwnershipSupportsMultipleMatchersUnderOneRuleID() throws {
        let report = try RuleTestHarness(
            Rules.memberReferenceOwnership(["observe", "stop"], allowed: .under("Sources/Owner"), id: "lifecycle")
        ).evaluate(
            [
                SourceInput.swift("Sources/Elsewhere/Leak.swift", component: "core", source: "func leak(_ value: API) { value.observe(); value.stop() }"),
            ]
        )

        #expect(report.violations.map(\.ruleID) == ["lifecycle", "lifecycle"])
        #expect(report.violations.map(\.evidence?.observed) == ["value.observe", "value.stop"])
    }

    @Test
    func declarationAndAccessShapersCoverInternalFunctionsAndSPI() throws {
        let ownership = Rules.declarationOwnership([.suffix("Adapter")], allowed: .under("Sources/Owner"), id: "adapter_owner")
        let publicAPI = Rules.publicAPIOwnership(allowed: .under("Sources/API"), id: "public_owner")
        let spi = Rules.spiOwnership(allowed: .under("Sources/Bridge"), id: "spi_owner")
        let report = try RuleTestHarness(RuleSet { ownership; publicAPI; spi }).evaluate(
            [
                SourceInput.swift("Sources/Elsewhere/Leak.swift", component: "core", source: "struct StorageAdapter {}\npublic func leaked() {}\n@_spi(Bridge) func bridge() {}"),
            ]
        )

        #expect(report.violations.map(\.ruleID) == ["adapter_owner", "public_owner", "spi_owner"])
    }

    @Test
    func singleDeclarationPassesForOneOwnedDeclaration() throws {
        let rule = Rules.singleDeclaration(
            NominalSymbol("TargetQuery"),
            owner: RelativePathPrefix("Sources/Plans")
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift("Sources/Plans/Target.swift", component: "plans", source: "struct TargetQuery {}"),
            ]
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func singleDeclarationFlagsDuplicatesAndForeignOwners() throws {
        let rule = Rules.singleDeclaration(
            NominalSymbol("TargetQuery"),
            owner: RelativePathPrefix("Sources/Plans")
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift("Sources/Plans/Target.swift", component: "plans", source: "struct TargetQuery {}"),
                SourceInput.swift("Sources/Plans/Duplicate.swift", component: "plans", source: "struct TargetQuery {}"),
                SourceInput.swift("Sources/Client/Foreign.swift", component: "client", source: "struct TargetQuery {}"),
            ]
        )

        #expect(report.violations.count == 2)
        #expect(report.violations.map(\.path.rawValue).sorted() == [
            "Sources/Client/Foreign.swift",
            "Sources/Plans/Duplicate.swift",
        ])
    }

    @Test
    func singleDeclarationMissingOwnerFilesIsConfigurationFailure() throws {
        let rule = Rules.singleDeclaration(
            NominalSymbol("TargetQuery"),
            owner: RelativePathPrefix("Sources/Missing")
        )

        #expect(throws: RuleEvaluationError.self) {
            _ = try RuleTestHarness(rule).evaluate(
                [
                    SourceInput.swift("Sources/Plans/Target.swift", component: "plans", source: "struct TargetQuery {}"),
                ]
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
            [
                SourceInput.swift(
                    "Sources/Builders/Builder.swift",
                    component: "core",
                    source: "func make() { _ = InterfaceObservation() }"
                ),
                SourceInput.swift(
                    "Sources/Feature/Rogue.swift",
                    component: "core",
                    source: "func rogue() { _ = InterfaceObservation() }"
                ),
            ]
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
            [
                SourceInput.swift(
                    "Sources/Boundary/Gate.swift",
                    component: "core",
                    source: "func load(data: Data) throws { _ = try JSONDecoder().decode(Thing.self, from: data) }"
                ),
                SourceInput.swift(
                    "Sources/Feature/Leak.swift",
                    component: "core",
                    source: "func leak(data: Data) throws { _ = try JSONDecoder().decode(Thing.self, from: data) }"
                ),
            ]
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Leak.swift"])
    }

    @Test
    func noAlternateAliasesFlagsAliasesOutsideFacade() throws {
        let rule = Rules.noAlternateAliases(
            NominalSymbol("TargetQuery"),
            allowing: .under(RelativePathPrefix("Sources/DSL"))
        )

        let harness = RuleTestHarness(rule)
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/DSL/Facade.swift", component: "core", source: "typealias Target = TargetQuery"),
            SourceInput.swift("Sources/Feature/Model.swift", component: "core", source: "typealias Value = OtherTarget"),
        ])
        #expect(passing.violations.isEmpty)

        let report = try harness.evaluate(
            [
                SourceInput.swift("Sources/DSL/Facade.swift", component: "core", source: "typealias Target = TargetQuery"),
                SourceInput.swift("Sources/Feature/Alias.swift", component: "core", source: "typealias MyTarget = TargetQuery"),
            ]
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(
            id: "no_alternate_aliases", path: "Sources/Feature/Alias.swift",
            location: SourcePosition(line: 1, column: 1),
            message: .exact("MyTarget aliases TargetQuery."),
            observed: .exact("typealias MyTarget = TargetQuery"),
            expectation: .exact("use TargetQuery directly")
        )))
    }

    @Test
    func canonicalTraversalFlagsRecursionOutsideOwners() throws {
        let recursiveSource = """
        func walk(tree: SyntaxTree) {
            if case .container = tree {
                walk(tree: tree)
            }
        }
        """
        let rule = Rules.canonicalTraversal(
            root: NominalSymbol("SyntaxTree"),
            structuralCase: EnumCaseSymbol("container"),
            owners: .under(RelativePathPrefix("Sources/Traversal")),
            id: "canonical_tree_traversal"
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift("Sources/Traversal/Owner.swift", component: "client", source: recursiveSource),
                SourceInput.swift("Sources/Client/Invalid.swift", component: "client", source: recursiveSource),
            ]
        )

        #expect(report.violations.map(\.rule.id) == ["canonical_tree_traversal"])
        #expect(report.violations.map(\.path.rawValue) == ["Sources/Client/Invalid.swift"])
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
        let repository = [
            SourceInput.swift("Sources/Feature/Walk.swift", component: "core", source: source),
        ]

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
            [
                SourceInput.swift(
                    "Sources/Feature/WrongSubject.swift",
                    component: "core",
                    source: """
                    func visit(tree: Tree, marker: Marker) {
                        if case .branch = marker {
                            visit(tree: tree, marker: marker)
                        }
                    }
                    """
                ),
            ]
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
            [
                SourceInput.swift(
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
                ),
            ]
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
            [
                SourceInput.swift(
                    "Sources/Feature/Unstructured.swift",
                    component: "core",
                    source: """
                    func visit(tree: Tree) {
                        let unrelated = Marker.branch
                        visit(tree: tree)
                    }
                    """
                ),
            ]
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func canonicalTraversalFlagsMutualRecursionOutsideOwners() throws {
        let rule = Rules.canonicalTraversal(
            root: NominalSymbol("SyntaxTree"),
            structuralCase: EnumCaseSymbol("container"),
            owners: .under(RelativePathPrefix("Sources/Traversal"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            [
                SourceInput.swift(
                    "Sources/Client/Mutual.swift",
                    component: "client",
                    source: """
                    func descend(tree: SyntaxTree) {
                        visit(tree: tree)
                    }

                    func visit(tree: SyntaxTree) {
                        if case .container = tree {
                            descend(tree: tree)
                        }
                    }
                    """
                ),
                SourceInput.swift(
                    "Sources/Client/OtherReceiver.swift",
                    component: "client",
                    source: """
                    struct Renderer {
                        let walker: Walker

                        func render(tree: SyntaxTree) {
                            walker.render(tree: tree)
                        }
                    }
                    """
                ),
            ]
        )

        #expect(report.violations.map(\.path.rawValue) == [
            "Sources/Client/Mutual.swift",
            "Sources/Client/Mutual.swift",
        ])
        #expect(Set(report.violations.compactMap { $0.message.split(separator: " ").first }) == ["descend", "visit"])
    }

}
