import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftLintFramework
import SwiftSyntax
import Testing

@Test func boundaryHelperMatchesDirectSwiftLintDiagnostics() throws {
    let sources: [SourceInput] = [
        .swift("Sources/Allowed.swift", source: "import Foundation\nimport UIKitExtras"),
        .swift("Sources/Denied.swift", source: "import UIKit\nimport struct SwiftUI.Text"),
        .swift("Sources/Conditional.swift", source: "#if os(iOS)\n@preconcurrency import UIKit\n#endif"),
        .swift("Sources/Disabled.swift", source: "// swiftlint:disable comparison.ui\nimport UIKit"),
    ]
    let authored = try RuleTestHarness(AuthoredUIBoundary.self).evaluate(sources)
    let native = try RuleTestHarness(DirectUIBoundary.self).evaluate(sources)
    #expect(authored == native)
    #expect(authored.count == 3)
    #expect(authored.filter(ViolationMatcher(
        id: "comparison.ui", path: "Sources/Denied.swift", line: 2, column: 1,
        reason: "Import SwiftUI is forbidden in this scope: the repository. Remove this dependency or move the code outside this scope."
    ).matches).count == 1)
}

private enum AuthoredUIBoundary: SyntaxRule {
    static let metadata = RuleMetadata(id: "comparison.ui", summary: "Keep UI imports at their boundary")
    static var body: SyntaxCheck { Rules.forbiddenImports(["UIKit", "SwiftUI"]) }
}

// Native reference: no Bumper query, context, fact, or check helper.
private struct DirectUIBoundary: SourceKitFreeRule {
    var configuration = SeverityConfiguration<Self>(.error)
    static let description = RuleDescription(
        identifier: "comparison.ui", name: "comparison.ui", description: "Keep UI imports at their boundary", kind: .lint
    )
    func validate(file: SwiftLintFile) -> [StyleViolation] {
        let visitor = ImportCollector(viewMode: .sourceAccurate)
        visitor.walk(file.syntaxTree)
        return visitor.nodes.compactMap { node in
            guard let module = node.path.first?.name.text, ["UIKit", "SwiftUI"].contains(module) else { return nil }
            return StyleViolation(
                ruleDescription: Self.description, severity: configuration.severity,
                location: Location(file: file, position: node.positionAfterSkippingLeadingTrivia),
                reason: "Import \(module) is forbidden in this scope: the repository. Remove this dependency or move the code outside this scope."
            )
        }
    }
}

private final class ImportCollector: SyntaxVisitor {
    private(set) var nodes: [ImportDeclSyntax] = []
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        nodes.append(node)
        return .skipChildren
    }
}
