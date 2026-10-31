import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Public policy coverage")
struct RuleSurfaceCoverageTests {
    @Test func publicSurfaceIncludesExtensionDefaultsAndSpecialMembers() throws {
        let harness = RuleTestHarness(Rules.publicAPIOwnership(allowed: .under("Sources/API"), id: "app.public_surface"))
        let model = SourceInput.swift("Sources/API/Model.swift", source: "public struct Model {}")
        let passing = try harness.evaluate([
            model,
            .swift("Sources/Implementation/Extra.swift", source: """
            extension Model {
                func helper() {}
                init(value: Int) { self.init() }
                subscript(index: Int) -> Int { index }
            }
            public extension Model { private func hidden() {} }
            """),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            model,
            .swift("Sources/Implementation/Extra.swift", source: """
            public extension Model {
                func helper() {}
                var computed: Int { 0 }
            }
            extension Model {
                public init(value: Int) { self.init() }
                public subscript(index: Int) -> Int { index }
            }
            """),
        ])
        #expect(failing.violations.count == 4)
        for (line, observed) in [(2, "public function helper"), (3, "public variable computed"), (6, "public initializer init"), (7, "public subscript subscript")] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "app.public_surface", path: "Sources/Implementation/Extra.swift",
                location: SourcePosition(line: line, column: 5), observed: .exact(observed)
            )).count == 1)
        }
    }

    @Test func disallowedTypesIncludeMemberAnnotations() throws {
        let harness = RuleTestHarness(Rules.disallowTypeReferences("Any", id: "app.named_types"))
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Model.swift", source: "struct Model { let payload: Int; var computed: Int { 0 } }"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Model.swift", source: """
            struct Model {
                let payload: Any
                var computed: Any { 0 }
                func load(value: [Any]) -> Any { value }
            }
            typealias Payload = Any
            """),
        ])
        #expect(failing.violations.count == 5)
        for (line, column) in [(2, 18), (3, 19)] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "app.named_types", path: "Sources/Model.swift",
                location: SourcePosition(line: line, column: column), observed: .exact("Any")
            )).count == 1)
        }
    }
}
