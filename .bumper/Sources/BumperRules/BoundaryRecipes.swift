import BumperBowlingCore
import SwiftSyntax

/// A repository's networking convention, expressed without an architecture engine.
public enum NetworkBoundaryRecipe: SyntaxRule {
    public static let metadata = RuleMetadata(id: "recipes.network", summary: "Networking has a named owner")
    public static var body: SyntaxCheck {
        Rules.importOwnership(["Network", "FoundationNetworking"], allowed: .under("Sources/Transport").union(.files(["Sources/TLS.swift"])))
    }
}

public enum SourceOwnersRecipe: SyntaxRule {
    public static let metadata = RuleMetadata(id: "recipes.owners", summary: "Included Swift files have exactly one owner")
    public static var body: SyntaxCheck {
        Rules.sourceOwnership([.under("Sources/Domain"), .under("Sources/Transport"), .files(["Sources/TLS.swift"])], scope: .under("Sources"))
    }
}

/// This repository convention rejects tuple syntax in explicitly exported contracts.
public enum NamedContractsRecipe: SyntaxRule {
    public static let metadata = RuleMetadata(id: "recipes.contracts", summary: "Exported contracts use named types")
    public static var body: SyntaxCheck {
        Rules.each(SyntaxQuery<DeclSyntax>()) { declaration in
            guard !declaration.node.contractTypes.isEmpty else { return [] }
            switch declaration.node.effectiveAccess {
            case .resolved(let access) where access >= .package:
                let tuples = declaration.node.contractTypes.flatMap { $0.descendants(of: TupleTypeSyntax.self) }.filter { $0.elements.count > 1 }
                return tuples.isEmpty ? [] : [declaration.failure(message: "Use a named type in this exported contract.")]
            case .unresolved:
                return [declaration.failure(message: "Access is unresolved. Keep the target declaration in this file or explicitly exclude this boundary.")]
            default: return []
            }
        }
    }
}

/// Optional function slots and onFoo callbacks state their outer isolation contract.
public enum CallbackIsolationRecipe: SyntaxRule {
    public static let metadata = RuleMetadata(id: "recipes.callbacks", summary: "Callback types declare actor or Sendable isolation")
    public static var body: SyntaxCheck {
        Rules.each(variables().filter { $0.node.lexicalPlacement != .local }) { declaration in
            declaration.node.bindings.compactMap { binding in
                guard let syntax = binding.typeAnnotation?.type,
                      case .resolved(let type) = declaration.file.resolveType(syntax), type.function != nil else { return nil }
                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text ?? ""
                let callbackName = name.hasPrefix("on") && name.dropFirst(2).first?.isUppercase == true
                guard type.isOptional || callbackName else { return nil }
                let isolated = type.attributes.contains { attribute in
                    if ["Sendable", "MainActor", "Swift.MainActor", "convention"].contains(attribute.attributeName.trimmedDescription) { return true }
                    guard case .resolved(let actor) = declaration.file.resolveType(attribute.attributeName) else { return false }
                    return actor.isGlobalActor
                }
                return isolated ? nil : declaration.file.failure(at: binding, message: "Declare @Sendable or a known global actor on the callback type.")
            }
        }
    }
}
