import BumperBowlingCore
import SwiftSyntax

/// Explicit keys cover direct stored instance properties. Synthesis stays allowed.
public struct ExplicitCodingKeysRule: SyntaxRule {
    public static let metadata = RuleMetadata(id: "persistence.coding_keys", summary: "Explicit keys cover direct stored instance properties")

    public static var body: SyntaxCheck {
        Rules.forEach(structs().inheriting("Codable")) { model in
            if let keys = SyntaxQuery<EnumDeclSyntax>().filter({ $0.name == "CodingKeys" }).members(of: model).first {
                let names = Set(SyntaxQuery<EnumCaseDeclSyntax>().members(of: keys).flatMap { $0.node.elements.map { $0.name.text } })
                for property in variables().storedMembers().filter({ variable in
                    !variable.node.modifiers.contains { ["static", "class"].contains($0.name.text) }
                }).members(of: model) {
                    for name in property.storedBindingNames {
                        Rules.require(names.contains(name), at: property, message: "Include \(name) in this type's CodingKeys")
                    }
                }
            }
        }
    }
}
