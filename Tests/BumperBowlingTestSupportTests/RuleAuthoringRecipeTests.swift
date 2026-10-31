import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftSyntax
import Testing

@Suite("Public rule authoring recipes")
struct RuleAuthoringRecipeTests {
    @Test func readmePreviewRuleHasPassingAndFailingFixtures() throws {
        let harness = RuleTestHarness(swiftUIPreviews)
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Features/Checkout/CheckoutView.swift", source: """
            struct CheckoutView: View {}
            #Preview { CheckoutView() }
            """),
            .swift("Sources/Other/BackgroundView.swift", source: "struct BackgroundView: View {}"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Features/Checkout/CheckoutView.swift", source: "struct CheckoutView: View {}"),
            .swift("Sources/Features/Checkout/Preview.swift", source: "#Preview { CheckoutView() }"),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "app.swiftui_preview", path: "Sources/Features/Checkout/CheckoutView.swift",
            location: SourcePosition(line: 1, column: 1),
            message: .exact("CheckoutView needs a #Preview that constructs CheckoutView.")
        )))
    }

    @Test func parsingStaysAtTheDeclaredBoundary() throws {
        let harness = RuleTestHarness(Rules.boundaryOnly(
            function: "Parser.parse", allowed: .under("Sources/Parsing"), id: "app.parsing_boundary"
        ))
        let parse = """
        func parse(text: String) {
            _ = Parser.parse(source: text)
        }
        """
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Parsing/Adapter.swift", source: parse),
            .swift("Sources/Rules/Policy.swift", source: "func inspect(file: SourceFileContext) { _ = file.syntax }"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Rules/Policy.swift", source: parse),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "app.parsing_boundary", path: "Sources/Rules/Policy.swift",
            location: SourcePosition(line: 2, column: 9),
            observed: .exact("call to Parser.parse in Sources/Rules/Policy.swift"),
            expectation: .exact("calls only inside the boundary scope")
        )))
    }

    @Test func arbitrarySyntaxUsesThePublicQuery() throws {
        let rule = Rules.forbid(
            SyntaxQuery<DictionaryExprSyntax>(),
            id: "analytics.named_payloads",
            summary: "Analytics payloads use named types.",
            scope: .under("Sources/Analytics")
        ) { _ in "Use a named analytics payload instead of a dictionary literal." }
        let harness = RuleTestHarness(rule)
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Analytics/Event.swift", source: "let payload = Event(name: \"tap\")"),
            SourceInput.swift("Sources/Other/Lookup.swift", source: "let lookup = [\"name\": \"tap\"]"),
        ])
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Analytics/Event.swift", source: "let payload = [\"name\": \"tap\"]"),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "analytics.named_payloads", path: "Sources/Analytics/Event.swift",
            location: SourcePosition(line: 1, column: 15),
            message: .exact("Use a named analytics payload instead of a dictionary literal.")
        )))
    }

    @Test(arguments: [false, true])
    func everyFeatureHasItsOwnDirectMembers(splitFiles: Bool) throws {
        let harness = RuleTestHarness(featureMembers)
        let valid = [
            "struct CheckoutFeature { struct CheckoutState {}; enum CheckoutAction {} }",
            "struct SearchFeature { struct State {}; enum Action {} }",
            "struct Unrelated {}",
        ]
        let passingFiles: [SourceInput] = splitFiles
            ? valid.enumerated().map { .swift("Sources/Features/Feature\($0.offset).swift", source: $0.element) }
            : [.swift("Sources/Features/Features.swift", source: valid.joined(separator: "\n"))]
        #expect(try harness.evaluate(passingFiles).violations.isEmpty)

        let invalid = [
            "struct CheckoutFeature { struct Nested { struct State {}; enum Action {} } }",
            "struct SearchFeature { struct State {} }",
            "struct PaymentFeature { struct PendingState {}; struct CompletedState {}; enum Action {} }",
            "struct Unrelated { enum Action {} }",
        ]
        let failingFiles: [SourceInput] = splitFiles
            ? invalid.enumerated().map { .swift("Sources/Features/Feature\($0.offset).swift", source: $0.element) }
            : [.swift("Sources/Features/Features.swift", source: invalid.joined(separator: "\n"))]
        let failing = try harness.evaluate(failingFiles)
        #expect(failing.violations.count == 4)
        for (index, name, suffix, count) in [(0, "CheckoutFeature", "State", 0), (0, "CheckoutFeature", "Action", 0), (1, "SearchFeature", "Action", 0), (2, "PaymentFeature", "State", 2)] {
            let path = splitFiles ? "Sources/Features/Feature\(index).swift" : "Sources/Features/Features.swift"
            #expect(failing.violations(matching: ViolationMatcher(
                id: "features.direct_members", path: try RelativeFilePath(path),
                location: SourcePosition(line: splitFiles ? 1 : index + 1, column: 1),
                message: .exact("\(name) needs one direct *\(suffix) declaration; found \(count)."),
                observed: .exact("\(name): \(count) direct *\(suffix) declarations"),
                expectation: .exact("one direct *State and one direct *Action declaration")
            )).count == 1)
        }
    }

    @Test func reservedSuffixAppliesOnlyToNominalDeclarations() throws {
        let rule = Rules.forbid(
            nominalDeclarations().filter {
                $0.node.asProtocol(NamedDeclSyntax.self)?.name.text.hasSuffix("Expr") == true
            }.excluding(.under("Sources/Expressions")),
            id: "expressions.owners", summary: "Expression declarations belong to the expression subsystem."
        ) { _ in "Declarations ending in Expr belong in Sources/Expressions." }
        let harness = RuleTestHarness(rule)
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Expressions/LiteralExpr.swift", source: "enum LiteralExpr {}"),
            .swift("Sources/Other/Helpers.swift", source: "func parseExpr() {}; let cachedExpr = 0; struct Helper {}"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Other/CallExpr.swift", source: "struct CallExpr {}"),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "expressions.owners", path: "Sources/Other/CallExpr.swift",
            location: SourcePosition(line: 1, column: 1),
            message: .exact("Declarations ending in Expr belong in Sources/Expressions.")
        )))
    }

    @Test func routesHaveExactlyOneRegistrationAcrossFiles() throws {
        let harness = RuleTestHarness(routeRegistrations)
        let routes = SourceInput.swift("Sources/App/Routes.swift", source: """
        enum AppRoute {
            case home
            case detail
        }
        """)
        let passing = try harness.evaluate([
            routes,
            SourceInput.swift("Sources/App/Home.swift", source: "register(.home)"),
            SourceInput.swift("Sources/App/Detail.swift", source: "register(.detail)"),
            SourceInput.swift("Sources/Other/Routes.swift", source: "enum AppRoute { case unrelated }"),
        ])
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate([
            routes,
            SourceInput.swift("Sources/App/Home.swift", source: "register(.home)"),
            SourceInput.swift("Sources/App/Duplicate.swift", source: "register(.home)"),
            SourceInput.swift("Sources/App/Other.swift", source: "other.register(.detail)"),
        ])
        #expect(failing.violations.count == 2)
        for (line, route, count) in [(2, "home", 2), (3, "detail", 0)] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "routes.registration", path: "Sources/App/Routes.swift",
                location: SourcePosition(line: line, column: 10),
                observed: .exact("\(route): \(count) registrations"),
                expectation: .exact("one bare register(.\(route)) call")
            )).count == 1)
        }
    }

    @Test func recursiveTraversalHasAnExplicitOwner() throws {
        let harness = RuleTestHarness(Rules.canonicalTraversal(
            root: "Tree", structuralCase: "branch", owners: .under("Sources/Traversal"), id: "tree.traversal_owner"
        ))
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Traversal/Walk.swift", source: """
            func walk(tree: Tree) {
                if case let .branch(children) = tree {
                    for child in children { walk(tree: child) }
                }
            }
            """),
            .swift("Sources/Features/Inspect.swift", source: """
            func inspect(tree: Tree) {
                if case .branch = tree { renderer.walk(tree: tree) }
            }
            """),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Features/Search.swift", source: """
            func search(tree: Tree) {
                if case let .branch(children) = tree {
                    for child in children { search(tree: child) }
                }
            }
            """),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "tree.traversal_owner", path: "Sources/Features/Search.swift",
            location: SourcePosition(line: 1, column: 1),
            observed: .exact("recursive call group over Tree matches .branch against tree"),
            expectation: .exact("traversal implemented only by the owner scope")
        )))
    }

    @Test func componentPolicyDoesNotInventOwnersForUnownedFiles() throws {
        let harness = RuleTestHarness(Rules.importOwnership(
            ["UI"], allowed: .component(RecipeComponent.ui), id: "components.ui_imports"
        ))
        let ui = SourceInput.swift("Sources/UI/Screen.swift", component: "ui", source: "import UI")
        let passing = try harness.evaluate([
            ui,
            SourceInput.swift("Sources/Domain/Model.swift", component: "domain", source: "struct Model {}"),
            SourceInput.swift("Sources/Other.swift", source: "struct Other {}"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            ui,
            SourceInput.swift("Sources/Domain/Model.swift", component: "domain", source: "import UI"),
            SourceInput.swift("Sources/Other.swift", source: "import UI"),
        ])
        #expect(failing.violations.count == 2)
        for path in ["Sources/Domain/Model.swift", "Sources/Other.swift"] {
            #expect(failing.contains(ViolationMatcher(
                id: "components.ui_imports", path: try RelativeFilePath(path),
                observed: .exact("import UI in \(path)"), expectation: .exact("imports only inside the allowed scope")
            )))
        }
    }
}

private enum RecipeComponent: String, ComponentKey { case ui }

private let swiftUIPreviews = Rules.each(
    structs().inheriting("View"),
    id: "app.swiftui_preview",
    summary: "Each feature view has a preview in the same file.",
    scope: .under("Sources/Features")
) { view in
    let previews = macroExpansions().named("Preview").matches(in: view.file)
    let viewName = view.node.name.text
    let hasPreview = previews.contains { preview in
        preview.node
            .descendants(of: FunctionCallExprSyntax.self)
            .map(\.calleeName)
            .contains(viewName)
    }
    return hasPreview ? [] : [view.failure(
        message: "\(viewName) needs a #Preview that constructs \(viewName)."
    )]
}

private let featureMembers = Rules.each(
    structs().filter { $0.node.name.text.hasSuffix("Feature") },
    id: "features.direct_members",
    summary: "Each feature declares one direct state type and one direct action type."
) { feature in
    let names = feature.node.memberBlock.members.compactMap { member in
        member.decl.as(StructDeclSyntax.self)?.name.text ?? member.decl.as(EnumDeclSyntax.self)?.name.text
    }
    return ["State", "Action"].compactMap { suffix in
        let count = names.filter { $0.hasSuffix(suffix) }.count
        guard count != 1 else { return nil }
        return feature.failure(
            message: "\(feature.node.name.text) needs one direct *\(suffix) declaration; found \(count).",
            evidence: ViolationEvidence(
                observed: "\(feature.node.name.text): \(count) direct *\(suffix) declarations",
                expectation: "one direct *State and one direct *Action declaration"
            )
        )
    }
}

private struct RouteInventory: Sendable {
    let cases: [SyntaxMatch<EnumCaseElementSyntax>]
    let registrations: [String]
}

private let routeInventory = DerivedFact("recipes.route_inventory") { context in
    RouteInventory(
        cases: context.repository.files.flatMap { file in
            SyntaxQuery<EnumDeclSyntax>().filter { $0.node.name.text == "AppRoute" }.matches(in: file).flatMap { route in
                route.node.memberBlock.members.flatMap { member in
                    member.decl.as(EnumCaseDeclSyntax.self)?.elements.map { SyntaxMatch(node: $0, file: file) } ?? []
                }
            }
        },
        registrations: context.repository.files.flatMap { file in
            functionCalls().matches(in: file).compactMap { call -> String? in
                guard call.node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "register",
                      call.node.arguments.count == 1,
                      let member = call.node.arguments.first?.expression.as(MemberAccessExprSyntax.self),
                      member.base == nil else { return nil }
                return member.declName.baseName.text
            }
        }
    )
}

private let routeRegistrations = Rules.repository(
    "routes.registration",
    summary: "Each AppRoute case has exactly one explicit registration.",
    scope: .files(["Sources/App/Routes.swift"])
) { subjects, context in
    let paths = Set(subjects.map(\.path))
    let inventory = try context.facts(routeInventory)
    let counts = Dictionary(grouping: inventory.registrations, by: { $0 }).mapValues(\.count)
    return inventory.cases.filter { paths.contains($0.file.path) }.compactMap { route in
        let name = route.node.name.text
        let count = counts[name, default: 0]
        guard count != 1 else { return nil }
        return route.failure(
            message: "\(name) needs exactly one registration; found \(count).",
            evidence: ViolationEvidence(observed: "\(name): \(count) registrations", expectation: "one bare register(.\(name)) call")
        )
    }
}
