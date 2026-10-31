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
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(name: DeclarationName, kind: String, access: AccessLevel, attributes: [AttributeName], path: RelativeFilePath, component: ComponentID?, location: SourcePosition?) {
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
        try context.facts(BuiltInFacts.declarationContracts).compactMap { contract in
            guard let name = try? DeclarationName(contract.name) else { return nil }
            return NamedDeclarationOccurrence(
                name: name, kind: StringMatcher.exact("property").matches(contract.kind) ? "variable" : contract.kind,
                access: contract.declaredAccess, attributes: contract.attributes,
                path: contract.path, component: contract.component, location: contract.location
            )
        }
    }
}

/// Explicit type syntax at an API or binding boundary. Values are spellings;
/// the provider intentionally makes no claim of compiler type resolution.
public struct TypeReferenceOccurrence: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case functionParameter, functionReturn, initializerParameter, localBinding, memberBinding, typeAlias
        case subscriptParameter, subscriptReturn, enumAssociatedValue, associatedType
    }
    public let kind: Kind
    public let subject: String
    public let type: TypeShape
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?
}

public struct TypeReferenceInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.type_references"
    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [TypeReferenceOccurrence] {
        try context.facts(BuiltInFacts.declarationContracts).flatMap { contract in
            contract.types.map { reference in
                TypeReferenceOccurrence(
                    kind: reference.kind.occurrenceKind(in: contract.context), subject: reference.name,
                    type: reference.type, path: contract.path, component: contract.component,
                    location: reference.location
                )
            }
        }
    }
}

private extension ContractTypeReference.Kind {
    func occurrenceKind(in context: LexicalContext) -> TypeReferenceOccurrence.Kind {
        switch self {
        case .functionParameter: .functionParameter
        case .functionReturn: .functionReturn
        case .initializerParameter: .initializerParameter
        case .property: context.placement == .typeMember ? .memberBinding : .localBinding
        case .subscriptParameter: .subscriptParameter
        case .subscriptReturn: .subscriptReturn
        case .typeAlias: .typeAlias
        case .enumAssociatedValue: .enumAssociatedValue
        case .associatedType: .associatedType
        }
    }
}

extension BuiltInFacts {
    public static let namedDeclarations = NamedDeclarationInventoryProvider()
    public static let typeReferences = TypeReferenceInventoryProvider()
}
