import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Repository rule subjects")
struct RepositorySubjectTests {
    @Test func outOfScopeDiagnosticsFailInsteadOfDisappearing() throws {
        let harness = RuleTestHarness(Rules.repository(
            "scoped.diagnostics", summary: "Findings anchor selected subjects.", scope: .under("Sources/Features")
        ) { _, context in
            context.repository.files.flatMap { file in
                structs().filter { $0.node.name.text == "Broken" }.matches(in: file).map {
                    $0.failure(message: "Broken declaration.")
                }
            }
        })
        #expect(try harness.evaluate(VirtualRepository {
            VirtualSourceFile.swift("Sources/Features/Good.swift", source: "struct Good {}")
            VirtualSourceFile.swift("Sources/Other.swift", source: "struct Other {}")
        }).violations.isEmpty)
        #expect(throws: RuleEvaluationError.diagnosticOutsideScope("scoped.diagnostics", "Sources/Other.swift")) {
            try harness.evaluate(VirtualRepository {
                VirtualSourceFile.swift("Sources/Features/Good.swift", source: "struct Good {}")
                VirtualSourceFile.swift("Sources/Other.swift", source: "struct Broken {}")
            })
        }
    }

    @Test func selectedSubjectsExcludeUnownedFilesFromComponentScopes() throws {
        let harness = RuleTestHarness(Rules.repository(
            "scoped.component", summary: "Only owned subjects belong to a component scope.", scope: .component(SubjectComponent.core)
        ) { subjects, _ in
            subjects.filter { $0.source == "import UI" }.map { file in
                RuleFailure(path: file.path, message: "UI import in core.")
            }
        })
        let unowned = VirtualSourceFile.swift("Sources/Unowned.swift", source: "import UI")
        #expect(try harness.evaluate(VirtualRepository {
            unowned
            VirtualSourceFile.swift("Sources/Core/Good.swift", component: "core", source: "struct Good {}")
        }).violations.isEmpty)
        let failing = try harness.evaluate(VirtualRepository {
            unowned
            VirtualSourceFile.swift("Sources/Core/Bad.swift", component: "core", source: "import UI")
        })
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "scoped.component", path: "Sources/Core/Bad.swift", message: .exact("UI import in core.")
        )))
    }
}

private enum SubjectComponent: String, ComponentKey { case core }
