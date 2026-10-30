import Foundation
import SwiftParser
import SwiftSyntax

public struct SwiftFileParser: Sendable {
    public init() {}

    /// Parses in-memory source into the same `SourceFileFacts` the scanner
    /// produces, under a placeholder path without component ownership.
    public func parse(_ source: String) -> SourceFileFacts {
        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(source: source, locationConverter: SourceLocationConverter(fileName: "", tree: tree))
        visitor.walk(tree)

        return SourceFileFacts(path: "InMemory.swift", source: source, nodes: visitor.nodes)
    }

    public func parseFile(
        at url: URL,
        relativePath: RelativeFilePath,
        component: ComponentID?
    ) throws -> SourceFileFacts {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw BumperError.unreadableFile(relativePath.rawValue)
        }

        let tree = Parser.parse(source: source)
        let visitor = SourceVisitor(source: source, locationConverter: SourceLocationConverter(fileName: relativePath.rawValue, tree: tree))
        visitor.walk(tree)

        return SourceFileFacts(
            path: relativePath,
            component: component,
            source: source,
            nodes: visitor.nodes
        )
    }
}

final class SourceVisitor: SyntaxAnyVisitor {
    private(set) var nodes: [CollectedSourceFact] = []
    private let locationConverter: SourceLocationConverter
    private let sourceBytes: [UInt8]
    private var ownerStack: [TypeName?] = []

    init(source: String, locationConverter: SourceLocationConverter) {
        self.sourceBytes = Array(source.utf8)
        self.locationConverter = locationConverter
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        if let module = node.bumper.importedModule {
            nodes.append(.importModule(module))
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        let type = node.bumper.nominalType(location: location)
        appendNominalType(type)
        nodes.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        ownerStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        let type = node.bumper.nominalType(location: location)
        appendNominalType(type)
        nodes.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        ownerStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        appendNominalType(node.bumper.nominalType(location: location))
        if let enumName = node.bumper.enumDeclaration {
            nodes.append(.enumDeclaration(enumName))
        }
        nodes.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        ownerStack.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        let type = node.bumper.nominalType(location: location)
        appendNominalType(type)
        nodes.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) {
        ownerStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        let type = node.bumper.nominalType(location: location)
        appendNominalType(type)
        nodes.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        ownerStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let declaration = node.bumper.extensionDeclaration(location: location(for: node))
        if let declaration {
            nodes.append(.extensionDeclaration(declaration))
        }
        ownerStack.append(declaration?.extendedType)
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) {
        ownerStack.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        nodes.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        let location = location(for: node)
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location).map(CollectedSourceFact.imperativeConstruct))
        nodes.append(contentsOf: node.bumper.publicDeclarations(location: location).map(CollectedSourceFact.publicDeclaration))
        nodes.append(contentsOf: node.bumper.storedProperties(owner: currentOwner, location: location).map(CollectedSourceFact.storedProperty))

        return .visitChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: AssignmentExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: InOutExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        recordSyntax(Syntax(node))
        nodes.append(contentsOf: node.bumper.imperativeConstructs(location: location(for: node)).map(CollectedSourceFact.imperativeConstruct))
        return .visitChildren
    }

    private func recordSyntax(_ node: Syntax) {
        nodes.append(node.bumper.syntaxNode(location: location(for: node), spelling: spelling(of: node)))
    }

    /// The node's source text with surrounding trivia trimmed, sliced from the
    /// original source bytes instead of re-rendering the subtree — the parse is
    /// full-fidelity, so the slice equals `trimmedDescription`.
    private func spelling(of node: Syntax) -> String? {
        let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = node.endPositionBeforeTrailingTrivia.utf8Offset
        guard start < end, end <= sourceBytes.count else { return nil }
        return String(bytes: sourceBytes[start..<end], encoding: .utf8)
    }

    private var currentOwner: TypeName? {
        ownerStack.reversed().compactMap { $0 }.first
    }

    private func appendNominalType(_ type: NominalType?) {
        if let type {
            nodes.append(.nominalType(type))
            ownerStack.append(type.name)
        } else {
            ownerStack.append(nil)
        }
    }

    private func location(for node: some SyntaxProtocol) -> SourcePosition {
        let sourceLocation = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SourcePosition(line: sourceLocation.line, column: sourceLocation.column)
    }
}
