import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftSyntax
import Testing

@Suite("Swift practice recipes")
struct SwiftPracticeRecipeTests {
    @Test func clocksAreConstructedAtTheDependencyBoundary() throws {
        let harness = RuleTestHarness(controllableClocks)
        let factory = SourceInput.swift("Sources/Dependencies/Clock.swift", source: "func makeClock() -> ContinuousClock { ContinuousClock() }")
        let passing = try harness.evaluate([
            factory,
            .swift("Sources/Library/Worker.swift", source: "func read<C: Clock>(clock: C) { _ = clock.now }"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            factory,
            .swift("Sources/Library/Worker.swift", source: "func read() { let clock = ContinuousClock(); _ = clock.now }"),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "dependencies.clock", path: "Sources/Library/Worker.swift",
            location: SourcePosition(line: 1, column: 27),
            observed: .exact("ContinuousClock(...) in Sources/Library/Worker.swift"),
            expectation: .exact("construction only inside the allowed scope")
        )))
    }

    @Test(arguments: [false, true])
    func valueOperationsBelongToTheSameType(splitFiles: Bool) throws {
        let harness = RuleTestHarness(valueOperationPairs)
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Values/Selection.swift", source: """
            struct Selection {
                var elements: Set<Int> = []
                mutating func formUnion(_ other: Self) { elements.formUnion(other.elements) }
                func union(_ other: Self) -> Self {
                    var result = self
                    result.formUnion(other)
                    return result
                }
            }
            struct Unrelated { func inspect() {} }
            """),
            .swift("Sources/Other/Collection.swift", source: "struct Collection { mutating func formUnion(_ other: Self) {} }"),
        ])
        #expect(passing.violations.isEmpty)
        let invalid = [
            "struct Missing {\n    mutating func formUnion(_ other: Self) {}\n}",
            "struct Nested {\n    mutating func formUnion(_ other: Self) {}\n    struct Helper { func union(_ other: Self) -> Self { self } }\n}",
            "struct MutatingCopy {\n    mutating func formUnion(_ other: Self) {}\n    mutating func union(_ other: Self) -> Self { self }\n}",
            "struct WrongReturn {\n    mutating func formUnion(_ other: Self) {}\n    func union(_ other: Self) {}\n}",
            "struct WrongParameter {\n    mutating func formUnion(_ other: Self) {}\n    func union(_ other: Int) -> Self { self }\n}",
            "struct StaticCopy {\n    mutating func formUnion(_ other: Self) {}\n    static func union(_ other: Self) -> Self { other }\n}",
        ]
        let files: [SourceInput] = splitFiles
            ? invalid.enumerated().map { .swift("Sources/Values/Value\($0.offset).swift", source: $0.element) }
            : [.swift("Sources/Values/Values.swift", source: invalid.joined(separator: "\n"))]
        let failing = try harness.evaluate(files)
        #expect(failing.violations.count == invalid.count)
        var precedingLines = 0
        for (index, source) in invalid.enumerated() {
            let path = splitFiles ? "Sources/Values/Value\(index).swift" : "Sources/Values/Values.swift"
            #expect(failing.violations(matching: ViolationMatcher(
                id: "api.value_operations", path: try RelativeFilePath(path),
                location: SourcePosition(line: splitFiles ? 2 : precedingLines + 2, column: 5),
                message: .exact("Provide union(_:) -> Self alongside formUnion(_:)."),
                observed: .exact("formUnion(_:) has no matching value-returning union(_:)"),
                expectation: .exact("a nonmutating instance method union(_ other: Self) -> Self on the same struct")
            )).count == 1)
            precedingLines += source.split(separator: "\n").count
        }
    }

    @Test func uncheckedConformancesStayAtTheSynchronizationBoundary() throws {
        let harness = RuleTestHarness(uncheckedSendableBoundary)
        let synchronized = """
        import Foundation
        final class LockedCounter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func increment() { lock.withLock { count += 1 } }
        }
        """
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Synchronization/Counter.swift", source: synchronized),
            .swift("Sources/Library/Counter.swift", source: "actor Counter { var count = 0 }"),
            .swift("Sources/Library/Value.swift", source: "struct Value: Sendable { let count: Int }"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Library/Counter.swift", source: synchronized),
            .swift("Sources/Library/Box.swift", source: "final class Box: @unchecked Swift.Sendable {}"),
        ])
        #expect(failing.violations.count == 2)
        for (path, line, column) in [("Sources/Library/Counter.swift", 2, 28), ("Sources/Library/Box.swift", 1, 18)] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "concurrency.unchecked_boundary", path: try RelativeFilePath(path),
                location: SourcePosition(line: line, column: column),
                message: .exact("Keep manually synchronized Sendable conformances in Sources/Synchronization.")
            )).count == 1)
        }
    }
}

private let controllableClocks = Rules.constructionOwnership(
    "ContinuousClock", allowed: .under("Sources/Dependencies"), id: "dependencies.clock"
)

private let valueOperationPairs = Rules.each(
    structs(), id: "api.value_operations",
    summary: "Selected value types offer matching in-place and value-returning union operations.",
    scope: .under("Sources/Values")
) { value in
    let methods = functions().members(of: value).map(\.node)
    return methods.compactMap { method -> RuleFailure? in
        let parameters = method.signature.parameterClause.parameters
        guard method.name.text == "formUnion", method.modifiers.contains(where: { $0.name.text == "mutating" }),
              parameters.count == 1, let parameter = parameters.first, parameter.type.trimmedDescription == "Self", parameter.firstName.text == "_",
              method.signature.returnClause == nil else { return nil }
        let hasCopy = methods.contains { candidate in
            let inputs = candidate.signature.parameterClause.parameters
            return candidate.name.text == "union"
                && !candidate.modifiers.contains { ["mutating", "static", "class"].contains($0.name.text) }
                && inputs.count == 1 && inputs.first?.firstName.text == parameter.firstName.text
                && inputs.first?.type.trimmedDescription == "Self"
                && candidate.signature.returnClause?.type.trimmedDescription == "Self"
        }
        return hasCopy ? nil : SyntaxMatch(node: method, file: value.file).failure(
            message: "Provide union(_:) -> Self alongside formUnion(_:).",
            evidence: ViolationEvidence(
                observed: "formUnion(_:) has no matching value-returning union(_:)",
                expectation: "a nonmutating instance method union(_ other: Self) -> Self on the same struct"
            )
        )
    }
}

private let uncheckedSendableBoundary = Rules.forbid(
    SyntaxQuery<AttributedTypeSyntax>().filter { type in
        ["Sendable", "Swift.Sendable"].contains(type.node.baseType.trimmedDescription)
            && type.node.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "unchecked" }
    }.excluding(.under("Sources/Synchronization")),
    id: "concurrency.unchecked_boundary",
    summary: "Unchecked Sendable conformances belong to manually synchronized adapters."
) { _ in
    "Keep manually synchronized Sendable conformances in Sources/Synchronization."
}
