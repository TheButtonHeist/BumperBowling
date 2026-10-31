import BumperBowlingTestSupport
import BumperRules
import Testing

@Test func parsingAlwaysReusesTheFrameworkTree() throws {
    let harness = RuleTestHarness(ParsingBoundaryRule.self)
    let passing = try harness.evaluate([
        .swift("Sources/BumperBowlingCore/SourceFileContext.swift", source: "func inspect(file: SwiftLintFile) { _ = file.syntaxTree }"),
    ])
    #expect(passing.isEmpty)
    let paths = ["Sources/BumperBowlingCore/SourceFileContext.swift", "Sources/BumperBowlingCore/NewRule.swift"]
    let failing = try harness.evaluate(paths.map { .swift($0, source: "func parse() { SwiftParser.Parser /* comment */ . parse(source: text) }") })
    #expect(failing.count == 2)
    for path in paths {
        #expect(failing.filter(ViolationMatcher(id: "bumper.parsing_boundary", path: path, line: 1, column: 16,
                                               reason: "Reuse file.syntax instead of parsing again").matches).count == 1)
    }
}

@Test func processConstructionStaysInItsFile() throws {
    let harness = RuleTestHarness(ProcessConstructionRule.self)
    let source = "func command() { _ = Process(); _ = Foundation /* comment */ . Process.init() }"
    let passing = try harness.evaluate([.swift("Sources/BumperBowlingCore/ConfigurationCommandRunner.swift", source: source)])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([.swift("Sources/BumperBowlingCore/BumperCommands.swift", source: source)])
    #expect(failing.count == 2)
    for column in [22, 37] {
        #expect(failing.filter(ViolationMatcher(id: "bumper.process_construction", path: "Sources/BumperBowlingCore/BumperCommands.swift", line: 1, column: column,
                                               reason: "Construct processes only in ConfigurationCommandRunner.swift").matches).count == 1)
    }
}

@Test func processExecutionUsesTheBoundedOrInteractiveMethod() throws {
    let harness = RuleTestHarness(ProcessExecutionRule.self)
    let path = "Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"
    let passing = try harness.evaluate([
        .swift(path, source: """
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
        .swift("Sources/BumperBowlingCore/BumperCommands.swift", source: "func lint() { engine.run() }"),
    ])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([.swift(path, source: """
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
    """)])
    #expect(failing.count == 5)
    for (line, column) in [(3, 13), (4, 9), (5, 9), (6, 29), (10, 54)] {
        #expect(failing.filter(ViolationMatcher(id: "bumper.process_execution", path: path, line: line, column: column,
                                               reason: "Launch and wait only in ConfigurationLoader.runProcess or runSwiftTests").matches).count == 1)
    }
}

@Test(arguments: [
    ("Sources/BumperBowlingCore/ConfigurationCommandRunner.swift", "BoundedOutputBuffer"),
    ("Sources/BumperBowlingCore/SyntaxQuery.swift", "SyntaxNodeCollector"),
    ("Sources/BumperBowlingCore/RuleDefinition.swift", "RuleSettings"),
])
func mutationExceptionsBelongToDeclarations(implementation: (String, String)) throws {
    let (path, owner) = implementation
    let harness = RuleTestHarness(ImmutableEngineStateRule.self)
    let passing = try harness.evaluate([.swift(path, source: """
    struct \(owner) { var state = 0 }
    struct Immutable { let value = 0; var computed: Int { value }; func work() { var local = 0; local += 1 } }
    """)])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([
        .swift(path, source: """
        struct \(owner) { var state = 0 }
        struct NewModel { var value = 0 { didSet {} } }
        extension \(owner) { struct Nested { var value = 0 } }
        """),
        .swift("Sources/BumperBowlingCore/Unrelated.swift", source: "struct \(owner) { var state = 0 }"),
    ])
    #expect(failing.count == 3)
    #expect(failing.filter(ViolationMatcher(id: "bumper.immutable_engine_state", path: path, line: 2, column: 19,
                                           reason: "Keep stored state immutable: value in NewModel").matches).count == 1)
    #expect(failing.filter { $0.ruleIdentifier == "bumper.immutable_engine_state" && $0.location.file == path && $0.location.line == 3 && $0.reason == "Keep stored state immutable: value in Nested" }.count == 1)
    #expect(failing.filter { $0.ruleIdentifier == "bumper.immutable_engine_state" && $0.location.file == "Sources/BumperBowlingCore/Unrelated.swift" && $0.location.line == 1 && $0.reason == "Keep stored state immutable: state in \(owner)" }.count == 1)
}
