import BumperBowlingCore
import BumperBowlingTestSupport
import Foundation
import SwiftLintFramework
import SwiftSyntax
import Testing

@Test func buildersComposeScopedChecksAndReusableMemberRequirements() throws {
    let harness = RuleTestHarness(MemberRequirements.self)
    let passing = try harness.evaluate([
        .swift("Sources/Models/Record.swift", source: "struct VersionedModel: Record { let id = 1; let name = \"\"; let version = 1 }\nstruct SimpleModel: Record { let id = 1; let name = \"\" }"),
        .swift("Sources/Other.swift", source: "struct Outside: Record {}; legacy()"),
    ])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([
        .swift("Sources/Models/Record.swift", source: "struct VersionedModel: Record { struct Nested { let id = 1; let name = \"\"; let version = 1 } }\nstruct SimpleModel: Record { let id = 1; let name = \"\"; let version = 1 }"),
        .swift("Sources/Legacy.swift", source: "legacy()"),
    ])
    #expect(failing.count == 5)
    #expect(failing.filter(ViolationMatcher(
        id: "builder.members", path: "Sources/Models/Record.swift", line: 2, column: 1,
        reason: "Only VersionedModel declares version"
    ).matches).count == 1)
    for name in ["id", "name", "version"] {
        #expect(failing.filter(ViolationMatcher(
            id: "builder.members", path: "Sources/Models/Record.swift", line: 1, column: 1,
            reason: "VersionedModel needs \(name)"
        ).matches).count == 1)
    }
    #expect(failing.filter(ViolationMatcher(
        id: "builder.members", path: "Sources/Legacy.swift", line: 1, column: 1, reason: "Replace legacy()"
    ).matches).count == 1)
}

private struct MemberRequirements: SyntaxRule {
    static let metadata = RuleMetadata(id: "builder.members", summary: "Compose a member contract and a related legacy-call restriction")

    static var body: SyntaxCheck {
        Rules.forEach(structs().inheriting("Record"), scope: .under("Sources/Models")) { model in
            Self.requiredMembers(of: model)
        }
        Rules.forbid(functionCalls().named("legacy"), scope: .files(["Sources/Legacy.swift"])) { _ in "Replace legacy()" }
    }

    @CheckBuilder static func requiredMembers(of model: SyntaxMatch<StructDeclSyntax>) -> SyntaxCheck {
        let fields = Set(variables().storedMembers().members(of: model).flatMap(\.storedBindingNames))
        for name in ["id", "name"] {
            Rules.require(fields.contains(name), at: model, message: "\(model.name) needs \(name)")
        }
        if let inherited = model.node.inheritanceClause?.inheritedTypes.first {
            switch inherited.type.trimmedDescription {
            case "Record":
                if model.name == "VersionedModel" {
                    Rules.require(fields.contains("version"), at: model, message: "\(model.name) needs version")
                } else {
                    Rules.require(!fields.contains("version"), at: model, message: "Only VersionedModel declares version")
                }
            default: Rules.files { _ in [] }
            }
        }
    }
}

@Test func aForeignSyntaxTreeCannotSupplyARequiredCompanion() throws {
    let harness = RuleTestHarness(OwnTreeCompanion.self)
    let passing = try harness.evaluate([.swift("Sources/Subject.swift", source: "struct Subject {}\n#Preview { Subject() }")])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([.swift("Sources/Subject.swift", source: "struct Subject {}")])
    #expect(failing.count == 1)
    #expect(failing.filter(ViolationMatcher(
        id: "builder.own_tree", path: "Sources/Subject.swift", line: 1, column: 1, reason: "Use this file's syntax"
    ).matches).count == 1)
}

private struct OwnTreeCompanion: SyntaxRule {
    static let metadata = RuleMetadata(id: "builder.own_tree", summary: "Custom queries must retain tree identity")
    static var body: SyntaxCheck {
        let foreign = SourceFileContext(file: SwiftLintFile(contents: "#Preview { Subject() }"), root: FileManager.default.temporaryDirectory)
        let foreignNode = macroExpansions().matches(in: foreign)[0].node
        let companions = SyntaxQuery<MacroExpansionExprSyntax> { file in
            let own = macroExpansions().matches(in: file)
            return own.isEmpty ? [SyntaxMatch(node: foreignNode, file: file)] : own
        }
        Rules.forEach(structs()) { subject in
            Rules.require(inSameFile: companions, at: subject, message: "Use this file's syntax")
        }
    }
}
