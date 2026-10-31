import BumperBowlingTestSupport
import BumperRules
import Testing

@Test func previewsMatchTheirViewsInTheSameFile() throws {
    let harness = RuleTestHarness(SwiftUIPreviewRule.self)
    let passing = try harness.evaluate([
        .swift("Sources/Features/DocumentView.swift", source: """
        struct DocumentView: View {}
        struct OtherView: View {}
        #Preview { DocumentView(); OtherView() }
        """),
        .swift("Sources/Other/Background.swift", source: "struct Background: View {}"),
        .swift("Sources/Features/DisabledView.swift", source: "// swiftlint:disable app.swiftui_preview\nstruct DisabledView: View {}"),
    ])
    #expect(passing.isEmpty)

    let failing = try harness.evaluate([
        .swift("Sources/Features/DocumentView.swift", source: """
        struct DocumentView: View {}
        #Preview { OtherView() }
        let value = DocumentView()
        """),
        .swift("Sources/Features/Preview.swift", source: "#Preview { DocumentView() }"),
    ])
    #expect(failing.count == 1)
    #expect(failing.filter(ViolationMatcher(
        id: "app.swiftui_preview", path: "Sources/Features/DocumentView.swift", line: 1, column: 1,
        reason: "DocumentView needs a #Preview that constructs DocumentView"
    ).matches).count == 1)
}
