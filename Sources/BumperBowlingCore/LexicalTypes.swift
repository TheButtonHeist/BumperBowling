import SwiftSyntax

/// Reasons syntax alone cannot resolve a type's outer shape.
public enum LexicalTypeFailure: Equatable, Sendable {
    case unknownName(String)
    case ambiguousName(String)
    case genericParameter(String)
    case unsupportedSyntax
    case foreignSyntax
    case cycle
    case depthLimit
}

public enum LexicalTypeResolution: Sendable {
    case resolved(LexicalType)
    case unresolved(LexicalTypeFailure)
}

/// An outer type after explicit optional, attribute, and same-file alias wrappers.
public struct LexicalType: Sendable {
    public let syntax: TypeSyntax
    public let declaration: DeclSyntax?
    public let isOptional: Bool
    public let attributes: [AttributeSyntax]
    public let aliases: [TypeAliasDeclSyntax]

    public var function: FunctionTypeSyntax? { syntax.as(FunctionTypeSyntax.self) }

    /// Written @globalActor evidence, not compiler identity or actor validity.
    public var isGlobalActor: Bool {
        declaration?.asProtocol(WithAttributesSyntax.self)?.attributes.contains {
            $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "globalActor"
        } == true
    }
}

public extension SourceFileContext {
    /// Resolve the outer shape only. Imported types and generic substitutions stay unresolved.
    func resolveType(_ type: TypeSyntax, maximumAliasDepth: Int = 32) -> LexicalTypeResolution {
        guard type.root.id == syntax.id else { return .unresolved(.foreignSyntax) }
        guard maximumAliasDepth >= 0 else { return .unresolved(.depthLimit) }
        return LexicalTypeResolver(declarations: syntax.descendants(of: DeclSyntax.self), maximumAliasDepth: maximumAliasDepth)
            .resolve(type)
    }
}

private struct LexicalTypeResolver {
    let declarations: [DeclSyntax]
    let maximumAliasDepth: Int

    func resolve(
        _ type: TypeSyntax,
        aliases: [TypeAliasDeclSyntax] = [],
        activeAliases: Set<SyntaxIdentifier> = [],
        remainingSteps: Int = 256,
        remainingQualifiedDepth: Int = 32
    ) -> LexicalTypeResolution {
        var current = type
        var optional = false
        var attributes: [AttributeSyntax] = []
        var aliasChain = aliases
        var activeAliases = activeAliases
        guard remainingSteps > 0 else { return .unresolved(.depthLimit) }
        for step in 0..<remainingSteps {
            if let attributed = current.as(AttributedTypeSyntax.self) {
                attributes += attributed.attributes.compactMap { $0.as(AttributeSyntax.self) }
                current = attributed.baseType
                continue
            }
            if let wrapped = current.as(OptionalTypeSyntax.self)?.wrappedType ?? current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self)?.wrappedType {
                optional = true
                current = wrapped
                continue
            }
            if let tuple = current.as(TupleTypeSyntax.self), tuple.elements.count == 1,
               let element = tuple.elements.first, element.firstName == nil {
                current = element.type
                continue
            }
            if let member = current.as(MemberTypeSyntax.self), member.baseType.trimmedDescription == "Swift", member.name.text == "Optional",
               case .unresolved(.unknownName) = declaration(named: "Swift", from: current),
               let wrapped = optionalArgument(member.genericArgumentClause) {
                optional = true
                current = wrapped
                continue
            }
            if current.is(FunctionTypeSyntax.self) || current.is(TupleTypeSyntax.self) || current.is(ArrayTypeSyntax.self) || current.is(DictionaryTypeSyntax.self) {
                return .resolved(LexicalType(syntax: current, declaration: nil, isOptional: optional, attributes: attributes, aliases: aliasChain))
            }
            let lookup: DeclarationLookup
            if let identifier = current.as(IdentifierTypeSyntax.self) {
                lookup = declaration(named: identifier.name.text, from: current)
                if identifier.name.text == "Optional", case .unresolved(.unknownName) = lookup,
                   let wrapped = optionalArgument(identifier.genericArgumentClause) {
                    optional = true
                    current = wrapped
                    continue
                }
                guard identifier.genericArgumentClause == nil else { return .unresolved(.unsupportedSyntax) }
            } else if let member = current.as(MemberTypeSyntax.self), member.genericArgumentClause == nil {
                guard remainingQualifiedDepth > 0 else { return .unresolved(.depthLimit) }
                switch resolve(member.baseType, aliases: aliasChain, activeAliases: activeAliases, remainingSteps: remainingSteps - step - 1,
                               remainingQualifiedDepth: remainingQualifiedDepth - 1) {
                case .resolved(let base):
                    guard !base.isOptional, base.attributes.isEmpty,
                          let owner = base.declaration?.asProtocol(DeclGroupSyntax.self),
                          base.declaration?.asProtocol(WithGenericParametersSyntax.self)?.genericParameterClause == nil else {
                        return .unresolved(.unsupportedSyntax)
                    }
                    // Completed owner expansions count toward depth, not cycles.
                    aliasChain = base.aliases
                    lookup = select(owner.memberBlock.descendants(of: DeclSyntax.self).filter {
                        $0.parent?.is(MemberBlockItemSyntax.self) == true && enclosingScope(of: $0)?.id == owner.memberBlock.id
                            && typeName($0) == member.name.text
                    }, name: member.name.text)
                case .unresolved(let failure): return .unresolved(failure)
                }
            } else {
                return .unresolved(.unsupportedSyntax)
            }
            switch lookup {
            case .unresolved(let failure): return .unresolved(failure)
            case .resolved(let declaration):
                if let alias = declaration.as(TypeAliasDeclSyntax.self) {
                    guard activeAliases.insert(alias.id).inserted else { return .unresolved(.cycle) }
                    guard aliasChain.count < maximumAliasDepth else { return .unresolved(.depthLimit) }
                    guard alias.genericParameterClause == nil else { return .unresolved(.unsupportedSyntax) }
                    aliasChain.append(alias)
                    current = alias.initializer.value
                    continue
                }
                guard declaration.isProtocol(DeclGroupSyntax.self) else { return .unresolved(.unsupportedSyntax) }
                return .resolved(LexicalType(syntax: current, declaration: declaration, isOptional: optional, attributes: attributes, aliases: aliasChain))
            }
        }
        return .unresolved(.depthLimit)
    }

    private func declaration(named name: String, from node: TypeSyntax) -> DeclarationLookup {
        let candidates = declarations.filter { typeName($0) == name }
        var scopes = node.ancestors[...]
        var extensions: Set<SyntaxIdentifier> = []
        while let ancestor = scopes.first {
            scopes = scopes.dropFirst()
            if let extensionDecl = ancestor.as(ExtensionDeclSyntax.self) {
                guard extensions.insert(extensionDecl.id).inserted, extensions.count <= 32 else { return .unresolved(.depthLimit) }
                guard let target = extensionDecl.sameFileExtendedNominal,
                      let owner = target.asProtocol(DeclGroupSyntax.self) else { return .unresolved(.unsupportedSyntax) }
                scopes = ([Syntax(owner.memberBlock), Syntax(target)] + target.ancestors)[...]
                continue
            }
            if ancestor.asProtocol(WithGenericParametersSyntax.self)?.genericParameterClause?.parameters.contains(where: { $0.name.text == name }) == true {
                return .unresolved(.genericParameter(name))
            }
            if let owner = ancestor.as(DeclSyntax.self), owner.isProtocol(DeclGroupSyntax.self), candidates.contains(where: {
                enclosingScope(of: $0)?.parent?.as(ExtensionDeclSyntax.self)?.sameFileExtendedNominal?.id == owner.id
            }) {
                return .unresolved(.unsupportedSyntax)
            }
            guard isScope(ancestor) else { continue }
            let matches = candidates.filter { enclosingScope(of: $0)?.id == ancestor.id }
            if !matches.isEmpty { return select(matches, name: name) }
        }
        return .unresolved(.unknownName(name))
    }

    private func select(_ candidates: [DeclSyntax], name: String) -> DeclarationLookup {
        guard let first = candidates.first else { return .unresolved(.unknownName(name)) }
        return candidates.count == 1 ? .resolved(first) : .unresolved(.ambiguousName(name))
    }

    private func typeName(_ node: DeclSyntax) -> String? {
        guard node.isProtocol(DeclGroupSyntax.self) || node.is(TypeAliasDeclSyntax.self) || node.is(AssociatedTypeDeclSyntax.self) else { return nil }
        return node.asProtocol(NamedDeclSyntax.self)?.name.text
    }

    private func enclosingScope(of node: DeclSyntax) -> Syntax? { node.ancestors.first(where: isScope) }

    private func isScope(_ node: Syntax) -> Bool {
        node.is(SourceFileSyntax.self) || node.is(MemberBlockSyntax.self) || node.is(CodeBlockSyntax.self) || node.is(ClosureExprSyntax.self)
    }

    private func optionalArgument(_ clause: GenericArgumentClauseSyntax?) -> TypeSyntax? {
        guard clause?.arguments.count == 1, let argument = clause?.arguments.first, case .type(let type) = argument.argument else { return nil }
        return type
    }

    private enum DeclarationLookup {
        case resolved(DeclSyntax)
        case unresolved(LexicalTypeFailure)
    }
}
