import SwiftSyntax

public protocol SyntaxPattern: Sendable {
    associatedtype Match: SyntaxProtocol
    func matches(in file: SourceFileContext) -> [SyntaxMatch<Match>]
    func matches<Root: SyntaxProtocol>(within root: SyntaxMatch<Root>) -> [SyntaxMatch<Match>]
}

public extension SyntaxPattern {
    func matches<Root: SyntaxProtocol>(within root: SyntaxMatch<Root>) -> [SyntaxMatch<Match>] {
        matches(in: root.file).filter { isDescendant($0, of: root) }
    }
}

public extension SyntaxPattern where Match: DeclSyntaxProtocol {
    /// Direct members only; declarations inside nested types do not belong to the owner.
    func members<Owner: DeclGroupSyntax>(of owner: SyntaxMatch<Owner>) -> [SyntaxMatch<Match>] {
        matches(within: owner).filter {
            $0.node.parent?.is(MemberBlockItemSyntax.self) == true
                && $0.node.parent?.parent?.parent?.id == owner.node.memberBlock.id
        }
    }
}

public struct SyntaxMatch<Node: SyntaxProtocol>: Sendable {
    public let node: Node
    public let file: SourceFileContext

    public init(node: Node, file: SourceFileContext) {
        self.node = node
        self.file = file
    }

    public func failure(message: String) -> RuleFailure {
        file.failure(at: node, message: message)
    }

}

public extension SyntaxMatch where Node: NamedDeclSyntax {
    var name: String { node.name.text }
}

public extension SyntaxMatch where Node == VariableDeclSyntax {
    var isMutable: Bool { node.bindingSpecifier.tokenKind == .keyword(.var) }
    var bindingNames: [String] { node.bindings.compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text } }
    var storedBindingNames: [String] {
        node.bindings.filter(\.isStored).compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
    }
}

public extension PatternBindingSyntax {
    var isStored: Bool {
        switch accessorBlock?.accessors {
        case nil: true
        case .accessors(let accessors):
            accessors.allSatisfy { [.keyword(.willSet), .keyword(.didSet)].contains($0.accessorSpecifier.tokenKind) }
        default: false
        }
    }
}

/// Composes over SwiftLint's cached SwiftSyntax tree. No parser or evaluator is owned here.
public struct SyntaxQuery<Node: SyntaxProtocol>: SyntaxPattern, Sendable {
    private let extract: @Sendable (SourceFileContext, Syntax) -> [SyntaxMatch<Node>]

    public init(_ extract: @escaping @Sendable (SourceFileContext) -> [SyntaxMatch<Node>]) {
        self.extract = { file, _ in extract(file) }
    }

    private init(extract: @escaping @Sendable (SourceFileContext, Syntax) -> [SyntaxMatch<Node>]) {
        self.extract = extract
    }

    public init() {
        self.init(extract: { file, root in
            root.descendants(of: Node.self).map { SyntaxMatch(node: $0, file: file) }
        })
    }

    public func matches(in file: SourceFileContext) -> [SyntaxMatch<Node>] {
        extract(file, Syntax(file.syntax))
    }

    public func matches<Root: SyntaxProtocol>(within root: SyntaxMatch<Root>) -> [SyntaxMatch<Node>] {
        extract(root.file, Syntax(root.node)).filter {
            isDescendant($0, of: root)
        }
    }

    public func filter(_ predicate: @escaping @Sendable (SyntaxMatch<Node>) -> Bool) -> Self {
        let extract = extract
        return Self(extract: { file, root in extract(file, root).filter(predicate) })
    }

    public func compactMap<Output: SyntaxProtocol>(
        _ transform: @escaping @Sendable (SyntaxMatch<Node>) -> Output?
    ) -> SyntaxQuery<Output> {
        let extract = extract
        return SyntaxQuery<Output>(extract: { file, root in
            extract(file, root).compactMap { match in
                transform(match).map { SyntaxMatch(node: $0, file: match.file) }
            }
        })
    }

    public func within(_ scope: RuleScope) -> Self {
        filter { scope.includes($0.file) }
    }

    public func excluding(_ scope: RuleScope) -> Self {
        filter { !scope.includes($0.file) }
    }

    public func containing<Related: SyntaxPattern>(_ related: Related) -> Self {
        filter { !related.matches(within: $0).isEmpty }
    }

    public func without<Related: SyntaxPattern>(
        inSameFile related: @escaping @Sendable (SyntaxMatch<Node>) -> Related
    ) -> Self {
        filter { subject in
            !related(subject).matches(in: subject.file).contains {
                $0.file.syntax.id == subject.file.syntax.id && $0.node.root.id == subject.file.syntax.id
            }
        }
    }
}

public func functions() -> SyntaxQuery<FunctionDeclSyntax> { SyntaxQuery() }
public func initializers() -> SyntaxQuery<InitializerDeclSyntax> { SyntaxQuery() }
public func typeAliases() -> SyntaxQuery<TypeAliasDeclSyntax> { SyntaxQuery() }
public func nominalDeclarations() -> SyntaxQuery<DeclSyntax> {
    SyntaxQuery<DeclSyntax>().filter { [.structDecl, .classDecl, .actorDecl, .enumDecl, .protocolDecl].contains($0.node.kind) }
}
public func structs() -> SyntaxQuery<StructDeclSyntax> { SyntaxQuery() }
public func variables() -> SyntaxQuery<VariableDeclSyntax> { SyntaxQuery() }
public func functionCalls() -> SyntaxQuery<FunctionCallExprSyntax> { SyntaxQuery() }
public func macroExpansions() -> SyntaxQuery<MacroExpansionExprSyntax> { SyntaxQuery() }

public extension SyntaxQuery where Node: DeclGroupSyntax {
    func inheriting(_ name: String) -> Self {
        filter { $0.node.inheritanceClause?.inheritedTypes.contains { $0.type.trimmedDescription == name } == true }
    }
}

public extension SyntaxQuery where Node == FunctionCallExprSyntax {
    /// Matches written callees. Receiver and alias identity are not resolved.
    func named(_ name: String) -> Self {
        filter { $0.node.calleeName == name }
    }
}

public extension SyntaxQuery where Node == MacroExpansionExprSyntax {
    func named(_ name: String) -> Self { filter { $0.node.macroName.text == name } }
}

public extension SyntaxQuery where Node == VariableDeclSyntax {
    func storedMembers() -> Self {
        filter { $0.node.parent?.is(MemberBlockItemSyntax.self) == true && !$0.storedBindingNames.isEmpty }
    }
}

public extension SyntaxProtocol {
    func descendants<Node: SyntaxProtocol>(of type: Node.Type) -> [Node] {
        let collector = SyntaxNodeCollector<Node>(viewMode: .sourceAccurate)
        collector.walk(self)
        return collector.nodes
    }

    var ancestors: [Syntax] {
        var result: [Syntax] = []
        var current = parent
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result
    }

    var enclosingNominalNames: [String] {
        ancestors.compactMap { ancestor in
            if let declaration = ancestor.asProtocol(NamedDeclSyntax.self),
               ancestor.isProtocol(DeclGroupSyntax.self) {
                return declaration.name.text
            }
            return ancestor.as(ExtensionDeclSyntax.self)?.extendedType.trimmedDescription
        }
    }
}

private final class SyntaxNodeCollector<Node: SyntaxProtocol>: SyntaxAnyVisitor {
    private(set) var nodes: [Node] = []

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if let match = node.as(Node.self) { nodes.append(match) }
        return .visitChildren
    }
}

private func isDescendant<Child: SyntaxProtocol, Root: SyntaxProtocol>(
    _ child: SyntaxMatch<Child>, of root: SyntaxMatch<Root>
) -> Bool {
    child.file.syntax.id == root.file.syntax.id && child.node.ancestors.contains { $0.id == root.node.id }
}

public extension FunctionCallExprSyntax {
    var calleeName: String { calledExpression.calleeName }
}

private extension ExprSyntax {
    var calleeName: String {
        if let reference = self.as(DeclReferenceExprSyntax.self) { return reference.baseName.text }
        if let member = self.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            guard let base = member.base else { return name }
            if base.as(DeclReferenceExprSyntax.self)?.baseName.text == "self" { return name }
            if let call = base.as(FunctionCallExprSyntax.self) { return call.calleeName + "." + name }
            return base.calleeName + "." + name
        }
        return trimmedDescription
    }
}
