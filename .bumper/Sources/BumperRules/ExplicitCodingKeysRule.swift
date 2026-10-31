import BumperBowlingCore
import SwiftSyntax

/// Explicit keys cover direct stored instance properties. Synthesis stays allowed.
public struct ExplicitCodingKeysRule: SyntaxRule {
    public var configuration = RuleSettings<Self>()
    public static let metadata = RuleMetadata(id: "persistence.coding_keys", summary: "Explicit keys cover direct stored instance properties")
    public init() {}

    public var body: SyntaxCheck {
        Rules.each(structs().inheriting("Codable")) { model in
            guard let keys = SyntaxQuery<EnumDeclSyntax>().filter({ $0.name == "CodingKeys" }).members(of: model).first else { return [] }
            let names = Set(SyntaxQuery<EnumCaseDeclSyntax>().members(of: keys).flatMap { $0.node.elements.map { $0.name.text } })
            return variables().storedMembers().filter { variable in
                !variable.node.modifiers.contains { ["static", "class"].contains($0.name.text) }
            }.members(of: model).flatMap { property in
                property.storedBindingNames.filter { !names.contains($0) }.map { name in
                    property.failure(message: "Include \(name) in this type's CodingKeys")
                }
            }
        }
    }
}
