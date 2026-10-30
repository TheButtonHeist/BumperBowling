import SwiftSyntax

/// Access derived from this file only. Unresolved values require more context,
/// such as a declaration in another file or compiler-expanded declarations.
public enum LexicalAccess: Equatable, Sendable {
    case resolved(AccessLevel)
    case unresolved(String)
}

public struct ContractTypeReference: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case functionParameter, functionReturn, initializerParameter, property
        case subscriptParameter, subscriptReturn, typeAlias, enumAssociatedValue, associatedType
    }
    public let kind: Kind
    public let name: String
    public let type: TypeShape
    /// Original syntax retains lexical scope for alias lookup and custom queries.
    public let syntax: TypeSyntax
    public let location: SourcePosition
}

/// An explicitly written declaration and its signature types, including
/// non-public declarations. Inferred types and generated members are absent.
public struct DeclarationContract: Equatable, Sendable {
    public let name: String
    public let kind: String
    public let context: LexicalContext
    public let explicitAccess: AccessLevel?
    public let effectiveAccess: LexicalAccess
    public let attributes: [AttributeName]
    public let types: [ContractTypeReference]
    public let path: RelativeFilePath
    public let component: ComponentID
    public let location: SourcePosition
}

public struct DeclarationContractsProvider: FactProvider {
    public let id: FactProviderID = "bumper.declaration_contracts"
    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [DeclarationContract] {
        context.repository.files.flatMap { $0.declarationContracts() }
    }
}

extension BuiltInFacts {
    public static let declarationContracts = DeclarationContractsProvider()
}

public extension SourceFileContext {
    func declarationContracts() -> [DeclarationContract] {
        let declarations = syntax.descendants(of: DeclSyntax.self)
        let access = DeclarationAccessResolver(declarations: declarations)
        return declarations.flatMap { declaration -> [DeclarationContract] in
            guard let details = contractDetails(declaration, file: self) else { return [] }
            return details.names.map { name in
                DeclarationContract(
                    name: name, kind: details.kind, context: declaration.bumper.lexicalContext,
                    explicitAccess: explicitAccess(declaration), effectiveAccess: access.resolve(declaration),
                    attributes: attributeNames(declaration.asProtocol(WithAttributesSyntax.self)?.attributes ?? []),
                    types: details.types.filter { !["property", "enumCase"].contains(details.kind) || $0.name == name }, path: path, component: component, location: position(of: declaration)
                )
            }
        }
    }
}

private func explicitAccess(_ declaration: DeclSyntax) -> AccessLevel? {
    let modifiers = declaration.asProtocol(WithModifiersSyntax.self)?.modifiers ?? []
    return modifiers.first { $0.detail == nil && AccessLevel(rawValue: $0.name.text) != nil }
        .flatMap { AccessLevel(rawValue: $0.name.text) }
}

private struct DeclarationAccessResolver {
    let declarations: [DeclSyntax]

    func resolve(_ declaration: DeclSyntax, visited: Set<SyntaxIdentifier> = []) -> LexicalAccess {
        guard !visited.contains(declaration.id) else { return .unresolved("Cyclic enclosing declarations") }
        let visited = visited.union([declaration.id])
        let modifiers = declaration.asProtocol(WithModifiersSyntax.self)?.modifiers ?? []
        if explicitAccess(declaration) == nil, modifiers.contains(where: { $0.name.tokenKind == .keyword(.override) }) {
            return .unresolved("Override access requires the overridden declaration")
        }
        if declaration.bumper.lexicalContext.placement == .local { return .resolved(.private) }
        let enclosing = declaration.ancestors.compactMap { $0.as(DeclSyntax.self) }.first {
            $0.nominalDeclaration != nil || $0.is(ExtensionDeclSyntax.self)
        }
        var level = explicitAccess(declaration) ?? .internal
        if let extensionNode = declaration.as(ExtensionDeclSyntax.self) {
            let name = extensionNode.extendedType.trimmedDescription
            let targets = declarations.filter { candidate in
                guard let nominal = candidate.nominalDeclaration else { return false }
                let names = candidate.bumper.lexicalContext.enclosingNominalNames.reversed()
                let qualified = (Array(names) + [nominal.name]).joined(separator: ".")
                return qualified == name
            }
            guard targets.count == 1, let target = targets.first else {
                return .unresolved("Extension target \(name) is not unique in this file")
            }
            return resolve(target, visited: visited)
        }
        if let enclosing {
            if enclosing.is(ProtocolDeclSyntax.self) || declaration.is(EnumCaseDeclSyntax.self) {
                return resolve(enclosing, visited: visited)
            }
            if let extensionNode = enclosing.as(ExtensionDeclSyntax.self), explicitAccess(declaration) == nil {
                level = explicitAccess(DeclSyntax(extensionNode)) ?? .internal
            }
            switch resolve(enclosing, visited: visited) {
            case .resolved(let cap): level = cappedAccess(level, by: cap)
            case .unresolved(let reason): return .unresolved(reason)
            }
        }
        return .resolved(level)
    }
}

private func cappedAccess(_ level: AccessLevel, by cap: AccessLevel) -> AccessLevel {
    level.visibilityRank <= cap.visibilityRank ? level : cap
}

private struct ContractDetails {
    let names: [String]
    let kind: String
    let types: [ContractTypeReference]
}

private func contractDetails(
    _ declaration: DeclSyntax, file: SourceFileContext
) -> ContractDetails? {
    func reference(_ kind: ContractTypeReference.Kind, _ name: String, _ type: TypeSyntax) -> ContractTypeReference {
        ContractTypeReference(kind: kind, name: name, type: type.bumper.typeShape, syntax: type, location: file.position(of: type))
    }
    func parameters(_ parameters: FunctionParameterListSyntax, kind: ContractTypeReference.Kind) -> [ContractTypeReference] {
        parameters.map { reference(kind, $0.secondName?.text ?? $0.firstName.text, $0.type) }
    }
    if let node = declaration.as(FunctionDeclSyntax.self) {
        var types = parameters(node.signature.parameterClause.parameters, kind: .functionParameter)
        if let result = node.signature.returnClause { types.append(reference(.functionReturn, node.name.text, result.type)) }
        return ContractDetails(names: [node.name.text], kind: "function", types: types)
    }
    if let node = declaration.as(InitializerDeclSyntax.self) {
        return ContractDetails(names: ["init"], kind: "initializer", types: parameters(node.signature.parameterClause.parameters, kind: .initializerParameter))
    }
    if let node = declaration.as(SubscriptDeclSyntax.self) {
        return ContractDetails(names: ["subscript"], kind: "subscript", types: parameters(node.parameterClause.parameters, kind: .subscriptParameter)
                + [reference(.subscriptReturn, "subscript", node.returnClause.type)])
    }
    if let node = declaration.as(VariableDeclSyntax.self) {
        var types: [ContractTypeReference] = []
        var sharedType: TypeSyntax?
        for binding in node.bindings.reversed() {
            if let annotation = binding.typeAnnotation {
                sharedType = annotation.type
            } else if binding.initializer != nil {
                sharedType = nil
            }
            if let sharedType { types.insert(reference(.property, binding.pattern.trimmedDescription, sharedType), at: 0) }
            if binding.initializer != nil { sharedType = nil }
        }
        return ContractDetails(names: node.bindings.map { $0.pattern.trimmedDescription }, kind: "property", types: types)
    }
    if let node = declaration.as(TypeAliasDeclSyntax.self) {
        return ContractDetails(names: [node.name.text], kind: "typealias", types: [reference(.typeAlias, node.name.text, node.initializer.value)])
    }
    if let node = declaration.as(EnumCaseDeclSyntax.self) {
        return ContractDetails(names: node.elements.map(\.name.text), kind: "enumCase", types: node.elements.flatMap { element in
            (element.parameterClause?.parameters.map { reference(.enumAssociatedValue, element.name.text, $0.type) }) ?? []
        })
    }
    if let node = declaration.as(AssociatedTypeDeclSyntax.self) {
        let types = node.initializer.map { [reference(.associatedType, node.name.text, $0.value)] } ?? []
        return ContractDetails(names: [node.name.text], kind: "associatedtype", types: types)
    }
    if let nominal = declaration.nominalDeclaration {
        return ContractDetails(names: [nominal.name], kind: nominal.kind.rawValue, types: [])
    }
    return nil
}
