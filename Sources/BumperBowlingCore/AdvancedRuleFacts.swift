import SwiftSyntax

/// A named declaration observed directly from Swift syntax. This deliberately
/// includes internal declarations so ownership and access policies are not
/// limited to the public API surface.
public struct NamedDeclarationOccurrence: Equatable, Sendable {
    public let name: DeclarationName
    public let kind: String
    public let access: AccessLevel
    public let attributes: [AttributeName]
    public let path: RelativeFilePath
    public let component: ComponentID
    public let location: SourcePosition?

    public init(name: DeclarationName, kind: String, access: AccessLevel, attributes: [AttributeName], path: RelativeFilePath, component: ComponentID, location: SourcePosition?) {
        self.name = name
        self.kind = kind
        self.access = access
        self.attributes = attributes
        self.path = path
        self.component = component
        self.location = location
    }

    public var isSPI: Bool { attributes.contains { StringMatcher.exact("_spi").matches($0) } }
}

public struct NamedDeclarationInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.named_declarations"
    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [NamedDeclarationOccurrence] {
        context.repository.files.flatMap(namedDeclarations(in:))
    }
}

/// Explicit type syntax at an API or binding boundary. Values are spellings;
/// the provider intentionally makes no claim of compiler type resolution.
public struct TypeReferenceOccurrence: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case functionParameter, functionReturn, initializerParameter, localBinding, typeAlias }
    public let kind: Kind
    public let subject: String
    public let type: TypeShape
    public let path: RelativeFilePath
    public let component: ComponentID
    public let location: SourcePosition?
}

public struct TypeReferenceInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.type_references"
    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [TypeReferenceOccurrence] {
        context.repository.files.flatMap { file in
            var occurrences: [TypeReferenceOccurrence] = []
            for match in functions().matches(in: file) {
                for parameter in match.node.signature.parameterClause.parameters {
                    occurrences.append(TypeReferenceOccurrence(kind: .functionParameter, subject: parameter.secondName?.text ?? parameter.firstName.text, type: parameter.type.bumper.typeShape, path: file.path, component: file.component, location: file.position(of: parameter)))
                }
                if let returnClause = match.node.signature.returnClause {
                    occurrences.append(TypeReferenceOccurrence(kind: .functionReturn, subject: match.node.name.text, type: returnClause.type.bumper.typeShape, path: file.path, component: file.component, location: file.position(of: returnClause.type)))
                }
            }
            for match in initializers().matches(in: file) {
                for parameter in match.node.signature.parameterClause.parameters {
                    occurrences.append(TypeReferenceOccurrence(kind: .initializerParameter, subject: parameter.secondName?.text ?? parameter.firstName.text, type: parameter.type.bumper.typeShape, path: file.path, component: file.component, location: file.position(of: parameter)))
                }
            }
            for match in variables().matches(in: file) {
                for binding in match.node.bindings where !match.node.bumper.isMemberDeclaration {
                    guard let type = binding.bumper.explicitTypeShape else { continue }
                    for name in binding.bumper.identifierName.map({ [$0] }) ?? [] {
                        occurrences.append(TypeReferenceOccurrence(kind: .localBinding, subject: name, type: type, path: file.path, component: file.component, location: file.position(of: binding)))
                    }
                }
            }
            for match in typeAliases().matches(in: file) {
                occurrences.append(TypeReferenceOccurrence(kind: .typeAlias, subject: match.node.name.text, type: match.node.bumper.aliasedTypeShape, path: file.path, component: file.component, location: file.position(of: match.node)))
            }
            return occurrences
        }
    }
}

extension BuiltInFacts {
    public static let namedDeclarations = NamedDeclarationInventoryProvider()
    public static let typeReferences = TypeReferenceInventoryProvider()
}

private func namedDeclarations(in file: SourceFileContext) -> [NamedDeclarationOccurrence] {
    func occurrence(_ name: String, _ kind: String, _ modifiers: DeclModifierListSyntax, _ attributes: AttributeListSyntax, _ node: some SyntaxProtocol) -> NamedDeclarationOccurrence? {
        guard let name = try? DeclarationName(name) else { return nil }
        return NamedDeclarationOccurrence(name: name, kind: kind, access: accessLevel(modifiers), attributes: attributeNames(attributes), path: file.path, component: file.component, location: file.position(of: node))
    }
    var result: [NamedDeclarationOccurrence] = []
    for node in SyntaxQuery<StructDeclSyntax>().matches(in: file) { if let value = occurrence(node.node.name.text, "struct", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } }
    for node in SyntaxQuery<ClassDeclSyntax>().matches(in: file) { if let value = occurrence(node.node.name.text, "class", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } }
    for node in SyntaxQuery<EnumDeclSyntax>().matches(in: file) { if let value = occurrence(node.node.name.text, "enum", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } }
    for node in SyntaxQuery<ProtocolDeclSyntax>().matches(in: file) { if let value = occurrence(node.node.name.text, "protocol", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } }
    for node in SyntaxQuery<ActorDeclSyntax>().matches(in: file) { if let value = occurrence(node.node.name.text, "actor", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } }
    for node in functions().matches(in: file) { if let value = occurrence(node.node.name.text, "function", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } }
    for node in typeAliases().matches(in: file) { if let value = occurrence(node.node.name.text, "typealias", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } }
    for node in variables().matches(in: file) { for name in node.node.bumper.bindingNames { if let value = occurrence(name, "variable", node.node.modifiers, node.node.attributes, node.node) { result.append(value) } } }
    return result
}
