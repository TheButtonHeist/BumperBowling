import BumperBowlingCore
import BumperBowlingTestSupport
import BumperRules
import Testing

@Test func codingKeysCoverDirectStoredInstanceProperties() throws {
    let harness = RuleTestHarness(ExplicitCodingKeysRule.self)
    let passing = try harness.evaluate([
        .swift("Sources/Record.swift", source: """
        struct Record: Codable {
            var title = ""
            var count = 0
            static let format = 1
            var display: String { title }
            struct Helper { var cache = 0 }
            enum CodingKeys: String, CodingKey { case title, count = "item_count" }
        }
        struct Synthesized: Codable { var title = "" }
        """),
    ])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([
        .swift("Sources/Record.swift", source: """
        struct Record: Codable {
            var title = ""
            var count = 0
            enum CodingKeys: String, CodingKey {
                case title
                enum Helper: String, CodingKey { case count }
            }
        }
        struct Other: Codable {
            var included = false
            var omitted = false
            enum CodingKeys: String, CodingKey { case included }
        }
        """),
        .swift("Sources/OtherKeys.swift", source: "enum CodingKeys: String, CodingKey { case count, omitted }"),
    ])
    #expect(failing.count == 2)
    for (line, name) in [(3, "count"), (11, "omitted")] {
        #expect(failing.filter(ViolationMatcher(
            id: "persistence.coding_keys", path: "Sources/Record.swift", line: line, column: 5,
            reason: "Include \(name) in this type's CodingKeys"
        ).matches).count == 1)
    }
}

@Test func routesHaveExactlyOneRegistrationAcrossFiles() throws {
    let harness = RuleTestHarness(RouteRegistrationsRule.self)
    let routes = SourceInput.swift("Sources/App/Routes.swift", source: """
    enum AppRoute {
        case home
        case detail
    }
    """)
    let passing = try harness.evaluate([
        routes,
        .swift("Sources/Registrations/Home.swift", source: "register(.home)"),
        .swift("Sources/Registrations/Detail.swift", source: "register(.detail)"),
        .swift("Sources/Other/Routes.swift", source: "enum AppRoute { case unrelated }"),
    ])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([
        routes,
        .swift("Sources/Registrations/Home.swift", source: "register(.home)"),
        .swift("Sources/Registrations/Duplicate.swift", source: "register(.home)"),
        .swift("Sources/App/Other.swift", source: "other.register(.detail)"),
    ])
    #expect(failing.count == 2)
    for (line, name, count) in [(2, "home", 2), (3, "detail", 0)] {
        #expect(failing.filter(ViolationMatcher(
            id: "routes.registration", path: routes.path, line: line, column: 10,
            reason: "\(name) needs exactly one registration; found \(count)"
        ).matches).count == 1)
    }
    // A companion edit must affect the next run; persisted violation caching is off.
    let repaired = try harness.evaluate([
        routes,
        .swift("Sources/Other/Registrations.swift", source: "register(.home); register(.detail)"),
    ])
    #expect(repaired.isEmpty)
}

@Test func aRequiredRepositorySubjectCannotSilentlyDisappear() {
    #expect(throws: BumperBowlingCore.BumperError.self) {
        try RuleTestHarness(RouteRegistrationsRule.self).evaluate([
            .swift("Sources/Other/Routes.swift", source: "enum AppRoute { case unrelated }"),
        ])
    }
}
