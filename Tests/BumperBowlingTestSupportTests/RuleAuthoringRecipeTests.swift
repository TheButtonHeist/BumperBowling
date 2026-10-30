import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftSyntax
import Testing

@Suite("Public rule authoring recipes")
struct RuleAuthoringRecipeTests {
    @Test func arbitrarySyntaxUsesThePublicQuery() throws {
        let rule = Rules.forbid(
            SyntaxQuery<DictionaryExprSyntax>(),
            id: "analytics.named_payloads",
            summary: "Analytics payloads use named types.",
            scope: .under("Sources/Analytics")
        ) { _ in "Use a named analytics payload instead of a dictionary literal." }
        let harness = RuleTestHarness(rule)
        let passing = try harness.evaluate(VirtualRepository {
            VirtualSourceFile.swift("Sources/Analytics/Event.swift", component: "app", source: "let payload = Event(name: \"tap\")")
            VirtualSourceFile.swift("Sources/Other/Lookup.swift", component: "app", source: "let lookup = [\"name\": \"tap\"]")
        })
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate(VirtualRepository {
            VirtualSourceFile.swift("Sources/Analytics/Event.swift", component: "app", source: "let payload = [\"name\": \"tap\"]")
        })
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "analytics.named_payloads", path: "Sources/Analytics/Event.swift",
            location: SourcePosition(line: 1, column: 15),
            message: .exact("Use a named analytics payload instead of a dictionary literal.")
        )))
    }

    @Test func everyFeatureHasItsOwnDirectMembers() throws {
        let harness = RuleTestHarness(featureMembers)
        let passing = try harness.evaluate(VirtualRepository {
            VirtualSourceFile.swift("Sources/Features/Features.swift", component: "app", source: """
            struct CheckoutFeature { struct State {}; enum Action {} }
            struct SearchFeature { struct State {}; enum Action {} }
            struct Unrelated {}
            """)
        })
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate(VirtualRepository {
            VirtualSourceFile.swift("Sources/Features/Features.swift", component: "app", source: """
            struct CheckoutFeature { struct Nested { struct State {}; enum Action {} } }
            struct SearchFeature { struct State {} }
            struct Unrelated { enum Action {} }
            """)
        })
        #expect(failing.violations.count == 3)
        for (line, name, missing) in [(1, "CheckoutFeature", "State"), (1, "CheckoutFeature", "Action"), (2, "SearchFeature", "Action")] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "features.direct_members", path: "Sources/Features/Features.swift",
                location: SourcePosition(line: line, column: 1),
                message: .exact("\(name) needs a direct \(missing) declaration."),
                observed: .exact(name), expectation: .exact("direct State and Action declarations")
            )).count == 1)
        }
    }

    @Test func routesHaveExactlyOneRegistrationAcrossFiles() throws {
        let harness = RuleTestHarness(routeRegistrations)
        let routes = VirtualSourceFile.swift("Sources/App/Routes.swift", component: "app", source: """
        enum AppRoute {
            case home
            case detail
        }
        """)
        let passing = try harness.evaluate(VirtualRepository {
            routes
            VirtualSourceFile.swift("Sources/App/Home.swift", component: "app", source: "register(.home)")
            VirtualSourceFile.swift("Sources/App/Detail.swift", component: "app", source: "register(.detail)")
        })
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate(VirtualRepository {
            routes
            VirtualSourceFile.swift("Sources/App/Home.swift", component: "app", source: "register(.home)")
            VirtualSourceFile.swift("Sources/App/Duplicate.swift", component: "app", source: "register(.home)")
            VirtualSourceFile.swift("Sources/App/Other.swift", component: "app", source: "other.register(.detail)")
        })
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
}

private let featureMembers = Rules.each(
    structs().filter { $0.node.name.text.hasSuffix("Feature") },
    id: "features.direct_members",
    summary: "Each feature declares its own State and Action."
) { feature in
    let names = feature.node.memberBlock.members.compactMap { member in
        member.decl.as(StructDeclSyntax.self)?.name.text ?? member.decl.as(EnumDeclSyntax.self)?.name.text
    }
    return ["State", "Action"].filter { !names.contains($0) }.map { missing in
        feature.failure(
            message: "\(feature.node.name.text) needs a direct \(missing) declaration.",
            evidence: ViolationEvidence(observed: feature.node.name.text, expectation: "direct State and Action declarations")
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
    summary: "Each AppRoute case has exactly one explicit registration."
) { context in
    let inventory = try context.facts(routeInventory)
    let counts = Dictionary(grouping: inventory.registrations, by: { $0 }).mapValues(\.count)
    return inventory.cases.compactMap { route in
        let name = route.node.name.text
        let count = counts[name, default: 0]
        guard count != 1 else { return nil }
        return route.failure(
            message: "\(name) needs exactly one registration; found \(count).",
            evidence: ViolationEvidence(observed: "\(name): \(count) registrations", expectation: "one bare register(.\(name)) call")
        )
    }
}
