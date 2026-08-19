import SwiftSyntax

public extension BumperSyntaxView where Node == IdentifierTypeSyntax {
    var typeName: String {
        node.name.text
    }
}

public extension BumperSyntaxView where Node == ImportDeclSyntax {
    var importedModuleName: String? {
        node.path.trimmedDescription.components(separatedBy: ".").first
    }

    var importedModule: ModuleName? {
        importedModuleName.flatMap { try? ModuleName($0) }
    }
}

extension BumperSyntaxView where Node == ClassDeclSyntax {
    func nominalType(location: SourcePosition?) -> NominalType? {
        makeNominalType(
            kind: .class,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause,
            location: location
        )
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .class, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == StructDeclSyntax {
    func nominalType(location: SourcePosition?) -> NominalType? {
        makeNominalType(
            kind: .struct,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause,
            location: location
        )
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .struct, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == EnumDeclSyntax {
    func nominalType(location: SourcePosition?) -> NominalType? {
        makeNominalType(
            kind: .enum,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause,
            location: location
        )
    }

    var enumDeclaration: DeclarationName? {
        try? DeclarationName(node.name.text)
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .enum, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == ProtocolDeclSyntax {
    func nominalType(location: SourcePosition?) -> NominalType? {
        makeNominalType(
            kind: .protocol,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause,
            location: location
        )
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .protocol, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == ActorDeclSyntax {
    func nominalType(location: SourcePosition?) -> NominalType? {
        makeNominalType(
            kind: .actor,
            name: node.name.text,
            modifiers: node.modifiers,
            attributes: node.attributes,
            inheritanceClause: node.inheritanceClause,
            location: location
        )
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        publicDeclaration(kind: .actor, name: node.name.text, modifiers: node.modifiers, attributes: node.attributes, location: location)
    }
}

extension BumperSyntaxView where Node == ExtensionDeclSyntax {
    func extensionDeclaration(location: SourcePosition?) -> ExtensionDeclaration? {
        guard let extendedType = try? TypeName(node.extendedType.trimmedDescription) else {
            return nil
        }

        return ExtensionDeclaration(
            extendedType: extendedType,
            access: accessLevel(node.modifiers),
            inheritedTypes: inheritedTypes(node.inheritanceClause),
            attributes: attributeNames(node.attributes),
            location: location
        )
    }
}

public extension BumperSyntaxView where Node == PatternBindingSyntax {
    var identifierName: String? {
        node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }

    var explicitTypeName: String? {
        node.typeAnnotation?.type.trimmedDescription
    }

    var hasAccessorBlock: Bool {
        node.accessorBlock != nil
    }
}

public extension BumperSyntaxView where Node == VariableDeclSyntax {
    var isMutableBinding: Bool {
        node.bindingSpecifier.tokenKind == .keyword(.var)
    }

    var isMemberDeclaration: Bool {
        node.parent?.as(MemberBlockItemSyntax.self) != nil
    }

    var bindingNames: [String] {
        node.bindings.compactMap { binding in
            binding.bumper.identifierName
        }
    }

    var explicitTypeNames: [String] {
        node.bindings.compactMap { binding in
            binding.bumper.explicitTypeName
        }
    }

    func storedProperties(owner: TypeName? = nil) -> [StoredProperty] {
        guard isMemberDeclaration else {
            return []
        }

        return node.bindings.compactMap { binding in
            guard !binding.bumper.hasAccessorBlock,
                  let name = binding.bumper.identifierName,
                  let declarationName = try? DeclarationName(name) else {
                return nil
            }

            let typeName = binding.bumper.explicitTypeName.flatMap { try? TypeName($0) }
            return StoredProperty(
                owner: owner,
                name: declarationName,
                type: typeName,
                access: accessLevel(node.modifiers),
                attributes: attributeNames(node.attributes),
                isMutable: isMutableBinding
            )
        }
    }

    func publicDeclarations(location: SourcePosition?) -> [PublicDeclaration] {
        guard isPublic(node.modifiers) else {
            return []
        }

        return node.bindings.compactMap { binding in
            guard let name = binding.bumper.identifierName,
                  let declarationName = try? DeclarationName(name) else {
                return nil
            }

            return PublicDeclaration(
                kind: .variable,
                name: declarationName,
                attributes: attributeNames(node.attributes),
                location: location
            )
        }
    }

    func storedProperties(owner: TypeName?, location: SourcePosition?) -> [StoredProperty] {
        storedProperties(owner: owner).map { property in
            StoredProperty(
                owner: property.owner,
                name: property.name,
                type: property.type,
                access: property.access,
                attributes: property.attributes,
                isMutable: property.isMutable,
                location: location
            )
        }
    }

    func imperativeConstructs(location: SourcePosition?) -> [ObservedImperativeConstruct] {
        isMutableBinding
            ? [ObservedImperativeConstruct(construct: .mutableBinding, location: location)]
            : []
    }
}

func publicDeclaration(
    kind: DeclarationKind,
    name: String,
    modifiers: DeclModifierListSyntax,
    attributes: AttributeListSyntax,
    location: SourcePosition?
) -> [PublicDeclaration] {
    guard isPublic(modifiers), let declarationName = try? DeclarationName(name) else {
        return []
    }

    return [
        PublicDeclaration(
            kind: kind,
            name: declarationName,
            attributes: attributeNames(attributes),
            location: location
        ),
    ]
}

private func makeNominalType(
    kind: DeclarationKind,
    name: String,
    modifiers: DeclModifierListSyntax,
    attributes: AttributeListSyntax,
    inheritanceClause: InheritanceClauseSyntax?,
    location: SourcePosition?
) -> NominalType? {
    guard let typeName = try? TypeName(name) else {
        return nil
    }

    return NominalType(
        kind: kind,
        name: typeName,
        access: accessLevel(modifiers),
        inheritedTypes: inheritedTypes(inheritanceClause),
        attributes: attributeNames(attributes),
        location: location
    )
}

private func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
    [.public, .open].contains(accessLevel(modifiers))
}

func accessLevel(_ modifiers: DeclModifierListSyntax) -> AccessLevel {
    let modifierNames = Set(modifiers.map(\.name.text))
    if modifierNames.contains("open") {
        return .open
    }
    if modifierNames.contains("public") {
        return .public
    }
    if modifierNames.contains("package") {
        return .package
    }
    if modifierNames.contains("fileprivate") {
        return .fileprivate
    }
    if modifierNames.contains("private") {
        return .private
    }
    return .internal
}

func attributeNames(_ attributes: AttributeListSyntax) -> [AttributeName] {
    attributes.compactMap { element in
        guard let name = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription else {
            return nil
        }
        return try? AttributeName(name)
    }
}

private func inheritedTypes(_ inheritanceClause: InheritanceClauseSyntax?) -> [TypeName] {
    inheritanceClause?.inheritedTypes.compactMap { inheritedType in
        try? TypeName(inheritedType.type.trimmedDescription)
    } ?? []
}
