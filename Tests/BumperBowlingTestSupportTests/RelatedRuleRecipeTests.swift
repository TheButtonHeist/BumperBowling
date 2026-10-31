import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftSyntax
import Testing

@Suite("Related syntax recipes")
struct RelatedRuleRecipeTests {
    @Test func previewsDoNotCreateLiveClients() throws {
        let harness = RuleTestHarness(previewDependencies)
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/UI/DocumentView.swift", source: """
            #Preview { DocumentView(client: .sample) }
            func bootstrap() { _ = Client.live() }
            """),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/UI/DocumentView.swift", source: """
            #Preview {
                DocumentView(client: Client.live())
                OtherView(client: Client.live())
            }
            #Preview { DocumentView(client: .sample) }
            """),
        ])
        #expect(failing.violations.count == 1)
        #expect(failing.contains(ViolationMatcher(
            id: "ui.preview_dependencies", path: "Sources/UI/DocumentView.swift",
            location: SourcePosition(line: 1, column: 1),
            message: .exact("Use a sample client in this preview.")
        )))
    }

    @Test func codingKeysCoverDirectStoredInstanceProperties() throws {
        let harness = RuleTestHarness(explicitCodingKeys)
        let passing = try harness.evaluate([
            SourceInput.swift("Sources/Persistence/Record.swift", source: """
            struct Record: Codable {
                var title = ""
                var count = 0
                static let format = 1
                var display: String { title }
                struct Helper { var cache = 0 }
                enum CodingKeys: String, CodingKey { case title, count = "item_count" }
            }
            struct Synthesized: Codable { var title = "" }
            """),
        ])
        #expect(passing.violations.isEmpty)
        let failing = try harness.evaluate([
            SourceInput.swift("Sources/Persistence/Record.swift", source: """
            struct Record: Codable {
                var title = ""
                var count = 0
                enum CodingKeys: String, CodingKey {
                    case title
                    enum Helper: String, CodingKey { case count }
                }
            }
            struct Other: Codable {
                var included = false
                var omitted = false
                enum CodingKeys: String, CodingKey { case included }
            }
            """),
            .swift("Sources/Persistence/OtherKeys.swift", source: "enum CodingKeys: String, CodingKey { case count, omitted }"),
        ])
        #expect(failing.violations.count == 2)
        for (line, property) in [(3, "count"), (11, "omitted")] {
            #expect(failing.violations(matching: ViolationMatcher(
                id: "persistence.coding_keys", path: "Sources/Persistence/Record.swift",
                location: SourcePosition(line: line, column: 5),
                message: .exact("Include \(property) in this type's CodingKeys."),
                observed: .exact("stored property \(property) has no direct CodingKeys case"),
                expectation: .exact("explicit CodingKeys lists every direct stored instance property")
            )).count == 1)
        }
    }
}

private let previewDependencies = Rules.forbid(
    macroExpansions().named("Preview").containing(functionCalls().named("Client.live")),
    id: "ui.preview_dependencies",
    summary: "Previews use sample clients."
) { _ in
    "Use a sample client in this preview."
}

private let explicitCodingKeys = Rules.each(
    structs().inheriting("Codable"),
    id: "persistence.coding_keys",
    summary: "Explicit CodingKeys covers each stored instance property.",
    scope: .under("Sources/Persistence")
) { model in
    let keys = SyntaxQuery<EnumDeclSyntax>().filter { $0.name == "CodingKeys" }.members(of: model)
    guard let keys = keys.first else { return [] }
    let cases = SyntaxQuery<EnumCaseDeclSyntax>().members(of: keys)
    let names = Set(cases.flatMap { $0.node.elements.map { $0.name.text } })
    return variables().storedMembers().filter { variable in
        !variable.node.modifiers.contains { ["static", "class"].contains($0.name.text) }
    }.members(of: model).flatMap { property in
        property.bindingNames.filter { !names.contains($0) }.map { name in
            property.failure(
                message: "Include \(name) in this type's CodingKeys.",
                evidence: ViolationEvidence(
                    observed: "stored property \(name) has no direct CodingKeys case",
                    expectation: "explicit CodingKeys lists every direct stored instance property"
                )
            )
        }
    }
}
