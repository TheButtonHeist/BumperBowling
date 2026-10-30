import Foundation
import SwiftSyntax

/// A typed query over one source file whose match node stays known through
/// composition.
public protocol SyntaxPattern: Sendable {
    associatedtype Match: SyntaxProtocol

    func matches(in file: SourceFileContext) -> [SyntaxMatch<Match>]
}

public struct SyntaxMatch<Node: SyntaxProtocol>: Sendable {
    public let node: Node
    public let file: SourceFileContext

    public init(node: Node, file: SourceFileContext) {
        self.node = node
        self.file = file
    }

    public var lexicalContext: LexicalContext {
        node.bumper.lexicalContext
    }

    public func failure(message: String, evidence: ViolationEvidence? = nil) -> RuleFailure {
        file.failure(at: node, message: message, evidence: evidence)
    }
}

public extension SyntaxMatch where Node == VariableDeclSyntax {
    var isMutable: Bool {
        node.bumper.isMutable
    }

    var bindingNames: [String] {
        node.bumper.bindingNames
    }
}

/// The generic composable query. Consumers extend it freely; Bumper does not
/// reserve query construction to internal code.
public struct SyntaxQuery<Node: SyntaxProtocol>: SyntaxPattern, Sendable {
    private let extract: @Sendable (SourceFileContext) -> [SyntaxMatch<Node>]

    public init(_ extract: @escaping @Sendable (SourceFileContext) -> [SyntaxMatch<Node>]) {
        self.extract = extract
    }

    /// All nodes of `Node`'s type in the file.
    public init() {
        self.init { file in
            file.syntax.descendants(of: Node.self).map { node in
                SyntaxMatch(node: node, file: file)
            }
        }
    }

    public func matches(in file: SourceFileContext) -> [SyntaxMatch<Node>] {
        extract(file)
    }

    public func filter(
        _ predicate: @escaping @Sendable (SyntaxMatch<Node>) -> Bool
    ) -> Self {
        let extract = extract
        return Self { file in
            extract(file).filter(predicate)
        }
    }

    public func compactMap<Output: SyntaxProtocol>(
        _ transform: @escaping @Sendable (SyntaxMatch<Node>) -> Output?
    ) -> SyntaxQuery<Output> {
        let extract = extract
        return SyntaxQuery<Output> { file in
            extract(file).compactMap { match in
                transform(match).map { output in
                    SyntaxMatch<Output>(node: output, file: file)
                }
            }
        }
    }

    public func within(_ scope: RuleScope) -> Self {
        let extract = extract
        return Self { file in
            scope.includes(file) ? extract(file) : []
        }
    }

    public func excluding(_ scope: RuleScope) -> Self {
        let extract = extract
        return Self { file in
            scope.includes(file) ? [] : extract(file)
        }
    }

    public func lexically(within scope: SyntaxScope) -> Self {
        filter { match in
            scope.includes(match.lexicalContext)
        }
    }

    public func lexically(excluding scope: SyntaxScope) -> Self {
        filter { match in
            !scope.includes(match.lexicalContext)
        }
    }
}

// MARK: - Query roots

public func functions() -> SyntaxQuery<FunctionDeclSyntax> {
    SyntaxQuery()
}

public func initializers() -> SyntaxQuery<InitializerDeclSyntax> {
    SyntaxQuery()
}

public func variables() -> SyntaxQuery<VariableDeclSyntax> {
    SyntaxQuery()
}

public func typeAliases() -> SyntaxQuery<TypeAliasDeclSyntax> {
    SyntaxQuery()
}

public func structs() -> SyntaxQuery<StructDeclSyntax> {
    SyntaxQuery()
}

public func macroExpansions() -> SyntaxQuery<MacroExpansionExprSyntax> {
    SyntaxQuery()
}

public func nominalDeclarations() -> SyntaxQuery<DeclSyntax> {
    SyntaxQuery<DeclSyntax> { file in
        file.syntax.descendants(of: DeclSyntax.self)
            .filter(\.isNominalDeclaration)
            .map { node in
                SyntaxMatch(node: node, file: file)
            }
    }
}

public func functionCalls() -> SyntaxQuery<FunctionCallExprSyntax> {
    SyntaxQuery()
}

// MARK: - Capability-specific operations

extension SyntaxQuery where Node == VariableDeclSyntax {
    /// Selects declarations with at least one stored member binding. Locals,
    /// globals, and computed properties are excluded; property observers remain.
    public func storedMembers() -> Self {
        filter { !$0.node.bumper.storedProperties().isEmpty }
    }
}

extension SyntaxQuery where Node: DeclGroupSyntax {
    public func inheriting(_ type: NominalSymbol) -> Self {
        filter { match in
            match.node.inheritanceClause?.inheritedTypes.contains { inheritedType in
                StringMatcher.exact(type.name).matches(inheritedType.type.trimmedDescription)
            } == true
        }
    }
}

extension SyntaxQuery where Node == FunctionDeclSyntax {
    public func named(_ name: FunctionSymbol) -> Self {
        filter { match in
            StringMatcher.exact(name.name).matches(match.node.name.text)
        }
    }

    public func taking(_ type: NominalSymbol) -> Self {
        filter { match in
            match.node.signature.parameterClause.parameters.contains { parameter in
                StringMatcher.exact(type.name).matches(parameter.type.trimmedDescription)
            }
        }
    }

    /// Functions whose body contains a locally dispatched call to their own
    /// name. A call on another receiver (`renderer.render(...)`) is not
    /// local dispatch and does not count.
    public func callingSelf() -> Self {
        filter { match in
            let name = match.node.name.text
            return match.node.locallyDispatchedCalleeNames.contains { callee in
                StringMatcher.exact(name).matches(callee)
            }
        }
    }
}

extension SyntaxQuery where Node == TypeAliasDeclSyntax {
    public func aliasing(_ type: NominalSymbol) -> Self {
        filter { match in
            StringMatcher.exact(type.name).matches(match.node.initializer.value.trimmedDescription)
        }
    }
}

extension SyntaxQuery where Node == MacroExpansionExprSyntax {
    public func named(_ name: MacroSymbol) -> Self {
        filter { match in
            StringMatcher.exact(name.name).matches(match.node.macroName.text)
        }
    }
}

// MARK: - Optional visitor and query utilities

extension SyntaxProtocol {
    /// Every descendant node of one syntax type, in source order.
    public func descendants<Node: SyntaxProtocol>(of type: Node.Type) -> [Node] {
        let collector = SyntaxNodeCollector<Node>(viewMode: .sourceAccurate)
        collector.walk(self)
        return collector.nodes
    }

    /// Ancestors from the nearest parent to the source file root.
    public var ancestors: [Syntax] {
        var ancestors: [Syntax] = []
        var current = parent
        while let node = current {
            ancestors.append(node)
            current = node.parent
        }
        return ancestors
    }

    /// The name of the nearest enclosing nominal or extension declaration.
    public var enclosingNominalName: String? {
        enclosingNominalNames.first
    }

    /// Enclosing nominal and extension names from nearest to outermost.
    public var enclosingNominalNames: [String] {
        ancestors.compactMap { ancestor in
            Syntax(ancestor).nominalDeclarationName
        }
    }
}

extension FunctionDeclSyntax {
    /// Base names of calls in this function's body that dispatch locally:
    /// bare references (`descend(...)`) or explicit self (`self.descend(...)`).
    /// Calls on any other receiver are excluded.
    var locallyDispatchedCalleeNames: [String] {
        guard let body else {
            return []
        }
        return body.descendants(of: FunctionCallExprSyntax.self).compactMap { call in
            if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                return reference.baseName.text
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               let base = member.base,
               base.is(DeclReferenceExprSyntax.self),
               StringMatcher.exact("self").matches(base.trimmedDescription) {
                return member.declName.baseName.text
            }
            return nil
        }
    }
}

extension FunctionCallExprSyntax {
    /// The called symbol, spelled as declared: `decode`, `JSONDecoder.decode`.
    /// Constructor-chained bases normalize (`JSONDecoder().decode` matches
    /// `JSONDecoder.decode`); `self.` bases drop.
    public var calleeName: String {
        calledExpression.calleeName
    }

}

private extension ExprSyntax {
    var calleeName: String {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }

        if let member = self.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            guard let base = member.base else {
                return name
            }
            if StringMatcher.exact("self").matches(base.trimmedDescription) {
                return name
            }
            if let baseCall = base.as(FunctionCallExprSyntax.self) {
                return baseCall.calleeName + "." + name
            }
            return base.calleeName + "." + name
        }

        return trimmedDescription
    }
}

private extension DeclSyntax {
    var isNominalDeclaration: Bool {
        nominalDeclaration != nil
    }
}

extension DeclSyntax {
    var nominalDeclaration: (name: String, kind: DeclarationKind)? {
        if let declaration = self.as(StructDeclSyntax.self) {
            return (declaration.name.text, .struct)
        }
        if let declaration = self.as(ClassDeclSyntax.self) {
            return (declaration.name.text, .class)
        }
        if let declaration = self.as(EnumDeclSyntax.self) {
            return (declaration.name.text, .enum)
        }
        if let declaration = self.as(ActorDeclSyntax.self) {
            return (declaration.name.text, .actor)
        }
        if let declaration = self.as(ProtocolDeclSyntax.self) {
            return (declaration.name.text, .protocol)
        }
        return nil
    }
}

private extension Syntax {
    var nominalDeclarationName: String? {
        if let declaration = self.as(StructDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = self.as(ClassDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = self.as(EnumDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = self.as(ActorDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = self.as(ProtocolDeclSyntax.self) {
            return declaration.name.text
        }
        if let declaration = self.as(ExtensionDeclSyntax.self) {
            return declaration.extendedType.trimmedDescription
        }
        return nil
    }
}

private final class SyntaxNodeCollector<Node: SyntaxProtocol>: SyntaxAnyVisitor {
    private(set) var nodes: [Node] = []

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if let match = node.as(Node.self) {
            nodes.append(match)
        }
        return .visitChildren
    }
}
