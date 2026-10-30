import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Repository policies")
struct BumperPolicyTests {
    @Test func parsingUsesExistingBoundaries() throws {
        let harness = RuleTestHarness(parsingBoundary)
        let source = """
        func parse(source: String) {
            _ = Parser.parse(source: source)
        }
        """
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/BumperBowlingCore/SourceFileContext.swift", component: "core", source: source),
            SourceInput.swift("Sources/BumperBowlingCore/SwiftFileParser.swift", component: "core", source: source),
            SourceInput.swift("Sources/BumperBowlingCore/FactProviders.swift", component: "core", source: "func derive(file: SourceFileContext) { _ = file.syntax }"),
        ])
        #expect(passing.violations.isEmpty)

        let paths = ["Sources/BumperBowlingCore/FactProviders.swift", "Sources/BumperBowlingCore/ArchitectureRuleEvaluation.swift"]
        let failing = try harness.evaluate(paths.map { SourceInput.swift($0, component: "core", source: source) })
        #expect(failing.violations.count == 2)
        for path in paths {
            let matcher = ViolationMatcher(
                id: "bumper.parsing_boundary", path: try RelativeFilePath(path),
                location: SourcePosition(line: 2, column: 9),
                expectation: .exact("calls only inside the boundary scope")
            )
            #expect(failing.violations(matching: matcher).count == 1)
        }
    }

    @Test func processConstructionUsesItsBoundary() throws {
        let harness = RuleTestHarness(processConstructionBoundary)
        let source = """
        func command() {
            _ = Process()
        }
        """
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/BumperBowlingCore/ConfigurationCommandRunner.swift", component: "core", source: source),
        ])
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate([
            SourceInput.swift("Sources/BumperBowlingCore/BumperCommands.swift", component: "core", source: source),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "bumper.process_construction", path: "Sources/BumperBowlingCore/BumperCommands.swift",
            location: SourcePosition(line: 2, column: 9),
            expectation: .exact("construction only inside the allowed scope")
        )))
    }

    @Test func executionUsesTheBoundedOrInteractiveMethod() throws {
        let harness = RuleTestHarness(processExecutionBoundary)
        let path = "Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"
        let passing = try harness.evaluate([
            SourceInput.swift(path, component: "core", source: """
            extension ConfigurationLoader {
                static func runProcess(_ process: Process) throws {
                    try process.run()
                    defer { process.waitUntilExit() }
                    process.waitUntilExit()
                }
                static func runSwiftTests() throws {
                    let process = Process()
                    try process.run()
                    process.waitUntilExit()
                }
            }
            """),
            SourceInput.swift("Sources/BumperBowlingCore/BumperCommands.swift", component: "core", source: "func lint() { engine.run() }"),
        ])
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate([
            SourceInput.swift(path, component: "core", source: """
            extension ConfigurationLoader {
                static func bypass(_ process: Process) throws {
                    try process.run()
                    process.launch()
                    process.waitUntilExit()
                    func runProcess() { process.waitUntilExit() }
                }
            }
            struct Other {
                func runProcess(_ process: Process) throws { try process.run() }
            }
            """),
        ])
        #expect(failing.violations.count == 5)
        for (line, column, observed) in [
            (3, 13, "process.run()"),
            (4, 9, "process.launch()"),
            (5, 9, "process.waitUntilExit()"),
            (6, 29, "process.waitUntilExit()"),
            (10, 54, "process.run()"),
        ] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "bumper.process_execution", path: try RelativeFilePath(path),
                location: SourcePosition(line: line, column: column), observed: .exact(observed),
                expectation: .exact("direct process execution stays in the bounded or interactive helper")
            )).count == 1)
        }
    }

    @Test(arguments: mutableImplementations)
    func mutationExceptionsApplyOnlyToTheirDeclarations(implementation: SourceInput) throws {
        let harness = RuleTestHarness(immutableEngineState)
        let ordinaryCode = """

        struct ImmutableModel {
            let value = 0
            var computed: Int { value }
            func work() { var local = 0; local += 1 }
        }
        """
        let passing = try harness.evaluate([
            SourceInput(path: implementation.path, component: implementation.component, source: implementation.source + ordinaryCode),
        ])
        #expect(passing.violations.isEmpty)

        let failing = try harness.evaluate([
            SourceInput(path: implementation.path, component: implementation.component, source: implementation.source + """

            struct NewModel { var value = 0 { didSet {} } }
            extension FactStore { struct Nested { var value = 0 } }
            """),
            SourceInput.swift("Sources/BumperBowlingCore/Unrelated.swift", component: "core", source: "class FactStore { var cache = 0 }"),
        ])
        #expect(failing.violations.count == 3)
        for owner in ["NewModel", "Nested"] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "bumper.immutable_engine_state", path: implementation.path,
                observed: .exact("var value in \(owner)"),
                expectation: .exact("immutable stored state outside the four named implementation declarations")
            )).count == 1)
        }
        #expect(failing.violations(matching: ViolationMatcher(
            id: "bumper.immutable_engine_state", path: "Sources/BumperBowlingCore/Unrelated.swift",
            location: SourcePosition(line: 1, column: 19), observed: .exact("var cache in FactStore")
        )).count == 1)
    }
}

private let mutableImplementations: [SourceInput] = [
    .swift("Sources/BumperBowlingCore/ConfigurationCommandRunner.swift", component: "core", source: """
    struct BoundedOutputBuffer {
        private(set) var data = Data()
        private(set) var hasExceededLimit = false
    }
    """),
    .swift("Sources/BumperBowlingCore/SwiftFileParser.swift", component: "core", source: """
    final class SourceVisitor: SyntaxAnyVisitor {
        private(set) var nodes: [CollectedSourceFact] = []
        private var ownerStack: [TypeName?] = []
    }
    """),
    .swift("Sources/BumperBowlingCore/SyntaxQuery.swift", component: "core", source: """
    final class SyntaxNodeCollector<Node: SyntaxProtocol>: SyntaxAnyVisitor {
        private(set) var nodes: [Node] = []
    }
    """),
    .swift("Sources/BumperBowlingCore/FactProviders.swift", component: "core", source: """
    final class FactStore {
        private var cache: [FactProviderID: Int] = [:]
        private var derivationPath: [FactProviderID] = []
        private var derivationMeasurements: [EvaluationTelemetry.Measurement] = []
    }
    """),
]
