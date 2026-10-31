import BumperBowlingCore

/// These are syntax spellings, not compiler identities or alias resolution.
public struct SwiftUIPreviewRule: SyntaxRule {
    public var configuration = RuleSettings<Self>()
    public static let metadata = RuleMetadata(
        id: "app.swiftui_preview", summary: "Each feature view has a matching preview in the same file"
    )
    public init() {}

    public var body: SyntaxCheck {
        Rules.forbid(
            structs().inheriting("View").without(inSameFile: { view in
                macroExpansions().named("Preview").containing(functionCalls().named(view.name))
            }),
            scope: .under("Sources/Features")
        ) { view in
            "\(view.name) needs a #Preview that constructs \(view.name)"
        }
    }
}
