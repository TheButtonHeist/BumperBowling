import SwiftLintFramework
import SwiftSyntax

public enum LexicalAccess: Equatable, Sendable {
    case resolved(AccessControlLevel)
    case unresolved
}

public enum LexicalPlacement: Sendable {
    case fileScope, typeMember, local
}

public extension SyntaxProtocol {
    var lexicalPlacement: LexicalPlacement {
        for ancestor in ancestors {
            if ancestor.is(CodeBlockSyntax.self) || ancestor.is(ClosureExprSyntax.self) { return .local }
            if ancestor.is(MemberBlockItemSyntax.self) { return .typeMember }
            if ancestor.is(SourceFileSyntax.self) { return .fileScope }
        }
        return .fileScope
    }
}

public extension DeclSyntaxProtocol {
    /// Ignore setter-only access; this is the declaration's written visibility.
    var explicitAccess: AccessControlLevel? {
        guard let modifier = asProtocol(WithModifiersSyntax.self)?.modifiers.accessLevelModifier(setter: false) else { return nil }
        return AccessControlLevel(description: modifier.name.text)
    }

    /// Written access, defaults, and same-file enclosing caps. Unknown extension targets and implicit overrides remain unresolved.
    var effectiveAccess: LexicalAccess { declarationAccess(DeclSyntax(self), visited: []) }

    /// Explicit parameter, return, binding, alias, payload, and associated-type-default syntax.
    var contractTypes: [TypeSyntax] {
        if let function = self.as(FunctionDeclSyntax.self) {
            return function.signature.parameterClause.parameters.map(\.type) + [function.signature.returnClause?.type].compactMap { $0 }
        }
        if let initializer = self.as(InitializerDeclSyntax.self) { return initializer.signature.parameterClause.parameters.map(\.type) }
        if let subscriptDecl = self.as(SubscriptDeclSyntax.self) {
            return subscriptDecl.parameterClause.parameters.map(\.type) + [subscriptDecl.returnClause.type]
        }
        if let variable = self.as(VariableDeclSyntax.self) { return variable.bindings.compactMap { $0.typeAnnotation?.type } }
        if let alias = self.as(TypeAliasDeclSyntax.self) { return [alias.initializer.value] }
        if let enumCase = self.as(EnumCaseDeclSyntax.self) {
            return enumCase.elements.flatMap { $0.parameterClause?.parameters.map(\.type) ?? [] }
        }
        if let associated = self.as(AssociatedTypeDeclSyntax.self) { return [associated.initializer?.value].compactMap { $0 } }
        return []
    }
}

private func declarationAccess(_ node: DeclSyntax, visited: Set<SyntaxIdentifier>) -> LexicalAccess {
    guard !visited.contains(node.id) else { return .unresolved }
    let visited = visited.union([node.id])
    let modifiers = node.asProtocol(WithModifiersSyntax.self)?.modifiers ?? []
    if node.explicitAccess == nil && modifiers.contains(where: { $0.name.text == "override" }) { return .unresolved }
    let enclosing = node.ancestors.first {
        $0.isProtocol(DeclGroupSyntax.self) || $0.is(CodeBlockSyntax.self) || $0.is(ClosureExprSyntax.self)
    }
    if enclosing?.is(CodeBlockSyntax.self) == true || enclosing?.is(ClosureExprSyntax.self) == true { return .resolved(.private) }
    if let extensionDecl = node.as(ExtensionDeclSyntax.self) {
        guard let target = extensionDecl.sameFileExtendedNominal else { return .unresolved }
        return declarationAccess(target, visited: visited)
    }
    guard let enclosing, let owner = enclosing.as(DeclSyntax.self) else { return .resolved(node.explicitAccess ?? .internal) }
    let cap = declarationAccess(owner, visited: visited)
    if owner.is(ProtocolDeclSyntax.self) || node.is(EnumCaseDeclSyntax.self) { return cap }
    guard case .resolved(let ownerAccess) = cap else { return .unresolved }
    // An extension modifier supplies member defaults; it does not cap explicitly visible members.
    let defaultAccess = owner.is(ExtensionDeclSyntax.self) ? owner.explicitAccess ?? .internal : .internal
    return .resolved(min(node.explicitAccess ?? defaultAccess, ownerAccess))
}

extension ExtensionDeclSyntax {
    var sameFileExtendedNominal: DeclSyntax? {
        guard let path = nominalPath(extendedType) else { return nil }
        let candidates = root.descendants(of: DeclSyntax.self).filter { declaration in
            guard declaration.isProtocol(DeclGroupSyntax.self), !declaration.is(ExtensionDeclSyntax.self),
                  let name = declaration.asProtocol(NamedDeclSyntax.self)?.name.text,
                  !declaration.ancestors.contains(where: { $0.is(CodeBlockSyntax.self) || $0.is(ClosureExprSyntax.self) }) else { return false }
            return Array(declaration.enclosingNominalNames.reversed()) + [name] == path
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}

private func nominalPath(_ type: TypeSyntax) -> [String]? {
    if let name = type.as(IdentifierTypeSyntax.self), name.genericArgumentClause == nil { return [name.name.text] }
    if let member = type.as(MemberTypeSyntax.self), member.genericArgumentClause == nil, let base = nominalPath(member.baseType) {
        return base + [member.name.text]
    }
    return nil
}
