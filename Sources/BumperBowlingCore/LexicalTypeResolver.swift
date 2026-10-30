import SwiftSyntax

public enum LexicalResolutionFailure: Equatable, Sendable {
    case unknownName(String)
    case ambiguousName(String)
    case unsupported(String)
    case cycle([String])
    case depthLimit(Int)
}

public struct LexicalAttributeFact: Equatable, Sendable {
    public let name: String
    /// A same-file declaration marked `@globalActor`, otherwise nil.
    public let globalActorLocation: SourcePosition?
    public let failure: LexicalResolutionFailure?
}

public struct LexicalTypeResolution: Equatable, Sendable {
    /// The last observed spelling. A non-nil failure means this is partial.
    public let type: TypeShape
    public let syntax: TypeSyntax
    public let aliasChain: [String]
    public let outerFunctionAttributes: [LexicalAttributeFact]
    public let failure: LexicalResolutionFailure?
}

/// Bounded, file-local lookup. This does not resolve imports, overloads,
/// inherited members, generic substitutions, or compiler type identity.
public struct LexicalTypeResolver: Sendable {
    private let file: SourceFileContext
    private let declarations: [DeclSyntax]

    public init(file: SourceFileContext) {
        self.file = file
        self.declarations = file.syntax.descendants(of: DeclSyntax.self)
    }

    public func resolve(_ type: TypeSyntax, maximumAliasDepth: Int = 32) -> LexicalTypeResolution {
        resolve(type, chain: [], visited: [], attributes: [], maximumDepth: max(0, maximumAliasDepth))
    }

    public func resolveAttribute(_ attribute: AttributeSyntax, maximumAliasDepth: Int = 32) -> LexicalAttributeFact {
        attributeFact(
            attribute.attributeName.trimmedDescription, from: Syntax(attribute),
            visited: [], depth: max(0, maximumAliasDepth)
        )
    }

    private func resolve(
        _ type: TypeSyntax, chain: [String], visited: Set<SyntaxIdentifier>,
        attributes: [LexicalAttributeFact], maximumDepth: Int
    ) -> LexicalTypeResolution {
        func result(_ failure: LexicalResolutionFailure? = nil) -> LexicalTypeResolution {
            let shape = type.bumper.typeShape
            let names = Set(attributes.map(\.name)).union(shape.outerFunctionAttributes)
            let resolvedShape = TypeShape(
                spelling: shape.spelling, referencedTypeNames: shape.referencedTypeNames,
                outerTypeName: shape.outerTypeName, attributes: shape.attributes.union(names),
                outerFunctionAttributes: shape.isFunction ? names : [], isFunction: shape.isFunction
            )
            return LexicalTypeResolution(
                type: resolvedShape, syntax: type, aliasChain: chain,
                outerFunctionAttributes: shape.isFunction ? attributes : [], failure: failure
            )
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            let facts = attributed.attributes.compactMap { $0.as(AttributeSyntax.self) }.map {
                resolveAttribute($0, maximumAliasDepth: maximumDepth)
            }
            return resolve(attributed.baseType, chain: chain, visited: visited,
                           attributes: attributes + facts, maximumDepth: maximumDepth)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return resolve(optional.wrappedType, chain: chain, visited: visited,
                           attributes: attributes, maximumDepth: maximumDepth)
        }
        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return resolve(optional.wrappedType, chain: chain, visited: visited,
                           attributes: attributes, maximumDepth: maximumDepth)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let element = tuple.elements.first, element.firstName == nil {
            return resolve(element.type, chain: chain, visited: visited,
                           attributes: attributes, maximumDepth: maximumDepth)
        }
        if type.is(FunctionTypeSyntax.self) || type.is(TupleTypeSyntax.self)
            || type.is(ArrayTypeSyntax.self) || type.is(DictionaryTypeSyntax.self) {
            return result()
        }
        if let member = type.as(MemberTypeSyntax.self),
           StringMatcher.exact("Swift").matches(member.baseType.as(IdentifierTypeSyntax.self)?.name.text ?? ""),
           StringMatcher.exact("Optional").matches(member.name.text),
           let arguments = member.genericArgumentClause?.arguments, arguments.count == 1,
           let argument = arguments.first, case .type(let wrapped) = argument.argument {
            return resolve(wrapped, chain: chain, visited: visited, attributes: attributes, maximumDepth: maximumDepth)
        }
        guard let name = type.as(IdentifierTypeSyntax.self) else {
            return result(.unsupported(type.trimmedDescription))
        }
        let candidates = lookup(name.name.text, from: Syntax(type))
        if StringMatcher.exact("Optional").matches(name.name.text), candidates.isEmpty,
           let arguments = name.genericArgumentClause?.arguments, arguments.count == 1,
           let argument = arguments.first, case .type(let wrapped) = argument.argument {
            return resolve(wrapped, chain: chain, visited: visited, attributes: attributes, maximumDepth: maximumDepth)
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            return result(candidates.isEmpty ? .unknownName(name.name.text) : .ambiguousName(name.name.text))
        }
        guard let alias = candidate.as(TypeAliasDeclSyntax.self) else {
            if candidate.nominalDeclaration != nil { return result() }
            if candidate.is(AssociatedTypeDeclSyntax.self) { return result(.unsupported("Associated type resolution")) }
            return result(.unsupported("\(name.name.text) is not a type declaration"))
        }
        guard !visited.contains(alias.id) else { return result(.cycle(chain + [alias.name.text])) }
        guard chain.count < maximumDepth else { return result(.depthLimit(maximumDepth)) }
        guard alias.genericParameterClause == nil, name.genericArgumentClause == nil else {
            return result(.unsupported("Generic alias substitution"))
        }
        return resolve(alias.initializer.value, chain: chain + [alias.name.text],
                       visited: visited.union([alias.id]), attributes: attributes, maximumDepth: maximumDepth)
    }

    private func attributeFact(
        _ name: String, from node: Syntax, visited: Set<SyntaxIdentifier>, depth: Int
    ) -> LexicalAttributeFact {
        func unresolved(_ failure: LexicalResolutionFailure) -> LexicalAttributeFact {
            LexicalAttributeFact(name: name, globalActorLocation: nil, failure: failure)
        }
        let candidates = lookup(name, from: node)
        guard candidates.count == 1, let declaration = candidates.first else {
            return unresolved(candidates.isEmpty ? .unknownName(name) : .ambiguousName(name))
        }
        if let alias = declaration.as(TypeAliasDeclSyntax.self) {
            guard !visited.contains(alias.id) else { return unresolved(.cycle([name])) }
            guard depth > 0 else { return unresolved(.depthLimit(0)) }
            guard alias.genericParameterClause == nil,
                  let target = alias.initializer.value.as(IdentifierTypeSyntax.self),
                  target.genericArgumentClause == nil else {
                return unresolved(.unsupported("Attribute alias substitution"))
            }
            let fact = attributeFact(target.name.text, from: Syntax(alias), visited: visited.union([alias.id]), depth: depth - 1)
            return LexicalAttributeFact(name: name, globalActorLocation: fact.globalActorLocation, failure: fact.failure)
        }
        let attributes = declaration.asProtocol(WithAttributesSyntax.self)?.attributes ?? []
        guard declaration.nominalDeclaration != nil, attributes.contains(where: {
            StringMatcher.exact("globalActor").matches($0.as(AttributeSyntax.self)?.attributeName.trimmedDescription ?? "")
        }) else {
            return unresolved(.unsupported("\(name) is not a lexical @globalActor declaration"))
        }
        return LexicalAttributeFact(name: name, globalActorLocation: file.position(of: declaration), failure: nil)
    }

    private func lookup(_ name: String, from node: Syntax) -> [DeclSyntax] {
        guard !name.isEmpty else { return [] }
        let matcher = StringMatcher.exact(name)
        for scope in node.ancestors {
            if let parameters = scope.asProtocol(WithGenericParametersSyntax.self)?.genericParameterClause,
               parameters.parameters.contains(where: { matcher.matches($0.name.text) }) { return [] }
            guard isScope(scope) else { continue }
            let matches = declarations.filter { declaration in
                declaredNames(declaration).contains { matcher.matches($0) }
                    && declaration.ancestors.first(where: isScope)?.id == scope.id
            }
            if !matches.isEmpty { return matches }
        }
        return []
    }
}

private func isScope(_ node: Syntax) -> Bool {
    node.is(SourceFileSyntax.self) || node.is(MemberBlockSyntax.self)
        || node.is(CodeBlockSyntax.self) || node.is(ClosureExprSyntax.self)
}

private func declaredNames(_ declaration: DeclSyntax) -> [String] {
    if let nominal = declaration.nominalDeclaration { return [nominal.name] }
    if let alias = declaration.as(TypeAliasDeclSyntax.self) { return [alias.name.text] }
    if let associated = declaration.as(AssociatedTypeDeclSyntax.self) { return [associated.name.text] }
    if let variable = declaration.as(VariableDeclSyntax.self) { return variable.bumper.bindingNames }
    if let function = declaration.as(FunctionDeclSyntax.self) { return [function.name.text] }
    return []
}
