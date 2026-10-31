import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftSyntax
import Testing

@Suite("Query composition contracts")
struct QueryCompositionTests {
    @Test func directMembersAndDescendantsHaveDifferentBoundaries() throws {
        let file = SourceFileContext(descriptor: SourceFileDescriptor(path: "Sources/Model.swift"), source: """
        struct Model {
            func direct() { build() }
            struct Helper { func nested() { build() } }
        }
        func outside() { build() }
        """)
        let model = try #require(structs().matches(in: file).first)
        #expect(functions().members(of: model).map(\.name) == ["direct"])
        #expect(functions().matches(within: model).map(\.name) == ["direct", "nested"])
        #expect(structs().matches(within: model).map(\.name) == ["Helper"])
        #expect(nominalDeclarations().matches(within: model).count == 1)
        let bodies = functions().compactMap { $0.node.body }.within(.under("Sources"))
        #expect(bodies.matches(within: model).count == 2)
        #expect(bodies.excluding(.under("Sources")).matches(within: model).isEmpty)
        let call = try #require(functionCalls().named("build").matches(within: model).first)
        #expect(call.file.position(of: call.node) == SourcePosition(line: 2, column: 21))
        #expect(call.node.root.id == file.syntax.id)
    }

    @Test func customPatternsKeepTheirDefaultSubtreeMatching() throws {
        let pattern = functions().containing(FileCalls(name: "build"))
        let harness = RuleTestHarness(Rules.forbid(
            pattern, id: "example.build", summary: "Build calls belong outside the selected functions."
        ) { "\($0.name) contains build." })
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Worker.swift", source: "func work() {}\nlet value = build()"),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Worker.swift", source: "func work() { build(); build() }"),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "example.build", path: "Sources/Worker.swift", location: SourcePosition(line: 1, column: 1),
            message: .exact("work contains build.")
        )))
        let file = SourceFileContext(descriptor: SourceFileDescriptor(path: "Sources/Worker.swift"), source: "func work() {}")
        #expect(functions().containing(functions().named("work")).matches(in: file).isEmpty)
    }

    @Test func sameFileMeansTheSameParsedSourceRatherThanTheSamePath() {
        let descriptor = SourceFileDescriptor(path: "Sources/Model.swift")
        let subject = SourceFileContext(descriptor: descriptor, source: "struct Model {}")
        let companion = SourceFileContext(descriptor: descriptor, source: "func companion() {}")
        let otherTree = SyntaxQuery<FunctionDeclSyntax> { _ in functions().matches(in: companion) }
        let missing = structs().without(inSameFile: { _ in otherTree })
        #expect(missing.matches(in: subject).map(\.name) == ["Model"])
        let present = structs().without(inSameFile: { _ in structs() })
        #expect(present.matches(in: subject).isEmpty)
        #expect(structs().containing(otherTree).matches(in: subject).isEmpty)
    }

    @Test func namedCallsReuseTheInventorySpelling() {
        let file = SourceFileContext(descriptor: SourceFileDescriptor(path: "Sources/Calls.swift"), source: """
        func work() {
            Client().load()
            self.load()
            other.load()
        }
        """)
        #expect(functionCalls().named("Client.load").matches(in: file).map { $0.file.position(of: $0.node) } == [SourcePosition(line: 2, column: 5)])
        #expect(functionCalls().named("load").matches(in: file).map { $0.file.position(of: $0.node) } == [SourcePosition(line: 3, column: 5)])
        #expect(functionCalls().named("").matches(in: file).isEmpty)
    }
}

private struct FileCalls: SyntaxPattern {
    let name: String

    func matches(in file: SourceFileContext) -> [SyntaxMatch<FunctionCallExprSyntax>] {
        functionCalls().named(name).matches(in: file)
    }
}
