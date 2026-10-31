import BumperBowlingCore

/// A preview must construct its view in the same file. This is a syntax check.
public enum SwiftUIPreviewRule: SyntaxRule {
    public static let metadata = RuleMetadata(
        id: "app.swiftui_preview",
        summary: "Each feature view has a matching preview in the same file"
    )

    public static var body: SyntaxCheck {
        Rules.forEach(structs().inheriting("View"), scope: .under("Sources/Features")) { view in
            Rules.require(
                inSameFile: macroExpansions().named("Preview")
                    .containing(functionCalls().named(view.name)),
                at: view,
                message: "\(view.name) needs a #Preview that constructs \(view.name)"
            )
        }
    }
}
