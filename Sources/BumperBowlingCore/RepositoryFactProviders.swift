import Foundation
import SwiftSyntax

// MARK: - Canonical per-file source facts

/// Canonical per-file facts (imports, nominal types, extensions, stored
/// properties, public declarations, imperative constructs, syntax nodes)
/// derived once from the already-parsed repository. No file is reparsed.
public struct SourceFileFactsProvider: FactProvider {
    public let id: FactProviderID = "bumper.source_files"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [SourceFileFacts] {
        context.repository.files.map { file in
            let visitor = SourceVisitor(source: file.source, locationConverter: file.locationConverter)
            visitor.walk(file.syntax)
            return SourceFileFacts(
                path: file.path,
                component: file.component,
                source: file.source,
                nodes: visitor.nodes
            )
        }
    }
}

// MARK: - Imports

public struct ImportOccurrence: Equatable, Sendable {
    public let module: ModuleName
    public let path: RelativeFilePath
    public let component: ComponentID?

    public init(module: ModuleName, path: RelativeFilePath, component: ComponentID?) {
        self.module = module
        self.path = path
        self.component = component
    }
}

public struct ImportInventory: Sendable {
    public let occurrences: [ImportOccurrence]

    public init(occurrences: [ImportOccurrence]) {
        self.occurrences = occurrences
    }
}

public struct ImportInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.imports"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> ImportInventory {
        ImportInventory(
            occurrences: try context.facts(BuiltInFacts.sourceFiles).flatMap { file in
                file.imports.map { module in
                    ImportOccurrence(module: module, path: file.path, component: file.component)
                }
            }
        )
    }
}

// MARK: - Nominal types, extensions, and stored properties

public struct NominalTypeOccurrence: Equatable, Sendable {
    public let type: NominalType
    public let path: RelativeFilePath
    public let component: ComponentID?

    public init(type: NominalType, path: RelativeFilePath, component: ComponentID?) {
        self.type = type
        self.path = path
        self.component = component
    }
}

public struct NominalTypeInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.nominal_types"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [NominalTypeOccurrence] {
        try context.facts(BuiltInFacts.sourceFiles).flatMap { file in
            file.nominalTypes.map { type in
                NominalTypeOccurrence(type: type, path: file.path, component: file.component)
            }
        }
    }
}

public struct ExtensionOccurrence: Equatable, Sendable {
    public let declaration: ExtensionDeclaration
    public let path: RelativeFilePath
    public let component: ComponentID?

    public init(declaration: ExtensionDeclaration, path: RelativeFilePath, component: ComponentID?) {
        self.declaration = declaration
        self.path = path
        self.component = component
    }
}

public struct ExtensionInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.extensions"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [ExtensionOccurrence] {
        try context.facts(BuiltInFacts.sourceFiles).flatMap { file in
            file.extensionDeclarations.map { declaration in
                ExtensionOccurrence(declaration: declaration, path: file.path, component: file.component)
            }
        }
    }
}

public struct StoredPropertyOccurrence: Equatable, Sendable {
    public let property: StoredProperty
    public let path: RelativeFilePath
    public let component: ComponentID?

    public init(property: StoredProperty, path: RelativeFilePath, component: ComponentID?) {
        self.property = property
        self.path = path
        self.component = component
    }
}

public struct StoredPropertyInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.stored_properties"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [StoredPropertyOccurrence] {
        try context.facts(BuiltInFacts.sourceFiles).flatMap { file in
            file.storedProperties.map { property in
                StoredPropertyOccurrence(property: property, path: file.path, component: file.component)
            }
        }
    }
}

// MARK: - Syntax-node inventory

public struct SyntaxNodeOccurrence: Equatable, Sendable {
    public let node: ObservedSyntaxNode
    public let path: RelativeFilePath
    public let component: ComponentID?

    public init(node: ObservedSyntaxNode, path: RelativeFilePath, component: ComponentID?) {
        self.node = node
        self.path = path
        self.component = component
    }
}

public struct SyntaxNodeInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.syntax_nodes"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [SyntaxNodeOccurrence] {
        try context.facts(BuiltInFacts.sourceFiles).flatMap { file in
            file.syntaxNodes.nodes.map { node in
                SyntaxNodeOccurrence(node: node, path: file.path, component: file.component)
            }
        }
    }
}

// MARK: - Effective access

public struct EffectiveAccessOccurrence: Equatable, Sendable {
    public let symbol: NominalSymbol
    public let declared: AccessLevel
    /// Declared access capped by every enclosing declaration's access.
    public let effective: AccessLevel
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(
        symbol: NominalSymbol,
        declared: AccessLevel,
        effective: AccessLevel,
        path: RelativeFilePath,
        component: ComponentID?,
        location: SourcePosition?
    ) {
        self.symbol = symbol
        self.declared = declared
        self.effective = effective
        self.path = path
        self.component = component
        self.location = location
    }
}

public struct EffectiveAccessProvider: FactProvider {
    public let id: FactProviderID = "bumper.effective_access"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [EffectiveAccessOccurrence] {
        context.repository.files.flatMap { file in
            nominalDeclarations().matches(in: file).compactMap { match in
                guard let type = match.node.nominalTypeFacts(location: file.position(of: match.node)) else {
                    return nil
                }

                let enclosingAccess = match.node.ancestors
                    .compactMap { ancestor in
                        DeclSyntax(ancestor)?.nominalTypeFacts(location: nil)?.access
                    }
                let effective = ([type.access] + enclosingAccess).min { lhs, rhs in
                    lhs.visibilityRank < rhs.visibilityRank
                } ?? type.access

                return EffectiveAccessOccurrence(
                    symbol: NominalSymbol(type.name.rawValue),
                    declared: type.access,
                    effective: effective,
                    path: file.path,
                    component: file.component,
                    location: file.position(of: match.node)
                )
            }
        }
    }
}

// MARK: - Enclosing declarations

public struct EnclosingDeclarationOccurrence: Equatable, Sendable {
    public let symbol: NominalSymbol
    /// Enclosing nominal or extension names from nearest to outermost.
    public let enclosing: [NominalSymbol]
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(
        symbol: NominalSymbol,
        enclosing: [NominalSymbol],
        path: RelativeFilePath,
        component: ComponentID?,
        location: SourcePosition?
    ) {
        self.symbol = symbol
        self.enclosing = enclosing
        self.path = path
        self.component = component
        self.location = location
    }
}

public struct EnclosingDeclarationsProvider: FactProvider {
    public let id: FactProviderID = "bumper.enclosing_declarations"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [EnclosingDeclarationOccurrence] {
        context.repository.files.flatMap { file in
            nominalDeclarations().matches(in: file).compactMap { match in
                match.node.nominalDeclaration.map { declaration in
                    EnclosingDeclarationOccurrence(
                        symbol: NominalSymbol(declaration.name),
                        enclosing: match.node.enclosingNominalNames.map { NominalSymbol($0) },
                        path: file.path,
                        component: file.component,
                        location: file.position(of: match.node)
                    )
                }
            }
        }
    }
}

// MARK: - Member references

public struct MemberReferenceOccurrence: Equatable, Sendable {
    /// The spelled base, when one exists: `renderer` in `renderer.render`.
    public let base: String?
    public let member: String
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(
        base: String?,
        member: String,
        path: RelativeFilePath,
        component: ComponentID?,
        location: SourcePosition?
    ) {
        self.base = base
        self.member = member
        self.path = path
        self.component = component
        self.location = location
    }
}

public struct MemberReferenceInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.member_references"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [MemberReferenceOccurrence] {
        context.repository.files.flatMap { file in
            SyntaxQuery<MemberAccessExprSyntax>().matches(in: file).map { match in
                MemberReferenceOccurrence(
                    base: match.node.base?.trimmedDescription,
                    member: match.node.declName.baseName.text,
                    path: file.path,
                    component: file.component,
                    location: file.position(of: match.node)
                )
            }
        }
    }
}

// MARK: - Component dependency edges

/// Component import edges resolved through the declared architecture.
public struct ComponentDependencyProvider: FactProvider {
    public let id: FactProviderID = "bumper.component_dependencies"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> [ComponentImportEdge] {
        let rules = try ArchitectureRules(configuration: context.configuration)
        return try context.facts(BuiltInFacts.imports).occurrences.compactMap { occurrence in
            guard let sourceComponent = occurrence.component else { return nil }
            return rules.componentByModule[occurrence.module].map { target in
                ComponentImportEdge(
                    sourceComponent: sourceComponent,
                    targetComponent: target,
                    importedModule: occurrence.module,
                    sourcePath: occurrence.path
                )
            }
        }
    }
}

// MARK: - Call graph and strongly connected components

/// One function parameter as spelled at the declaration boundary. These are
/// syntax facts; Bumper does not resolve aliases or inferred types.
public struct CallGraphParameterEvidence: Hashable, Sendable {
    public let localName: String
    public let typeSpelling: String

    public init(localName: String, typeSpelling: String) {
        self.localName = localName
        self.typeSpelling = typeSpelling
    }
}

/// One enum-like member pattern and the expression matched by that pattern.
/// For example, `if case .branch = tree` records (`branch`, `tree`).
public struct CasePatternEvidence: Hashable, Sendable {
    public let memberName: String
    public let subjectExpression: String

    public init(memberName: String, subjectExpression: String) {
        self.memberName = memberName
        self.subjectExpression = subjectExpression
    }
}

/// One function declaration as a call-graph node.
public struct CallGraphFunction: Hashable, Sendable {
    public let function: FunctionSymbol
    public let enclosingType: NominalSymbol?
    public let parameters: [CallGraphParameterEvidence]
    public let casePatterns: [CasePatternEvidence]
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(
        function: FunctionSymbol,
        enclosingType: NominalSymbol?,
        parameters: [CallGraphParameterEvidence],
        casePatterns: [CasePatternEvidence],
        path: RelativeFilePath,
        component: ComponentID?,
        location: SourcePosition?
    ) {
        self.function = function
        self.enclosingType = enclosingType
        self.parameters = parameters
        self.casePatterns = casePatterns
        self.path = path
        self.component = component
        self.location = location
    }
}

/// Groups of mutually recursive functions: every strongly connected
/// component of the locally-dispatched call graph, including direct
/// self-recursion. Calls on another receiver (`renderer.render(...)`) are
/// not local dispatch and never form edges.
public struct RecursiveCallGroups: Sendable {
    public let groups: [[CallGraphFunction]]

    public init(groups: [[CallGraphFunction]]) {
        self.groups = groups
    }
}

// ponytail: name-based resolution — a call edge links equal base names within
// the same enclosing type, or free functions repo-wide. Type-checked
// resolution needs SourceKit and is out of scope by spec.
public struct CallGraphSCCProvider: FactProvider {
    public let id: FactProviderID = "bumper.call_graph_sccs"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> RecursiveCallGroups {
        var nodes: [CallGraphFunction] = []
        var localCallees: [[String]] = []

        for file in context.repository.files {
            for match in functions().matches(in: file) {
                nodes.append(
                    CallGraphFunction(
                        function: FunctionSymbol(match.node.name.text),
                        enclosingType: match.node.enclosingNominalName.map { NominalSymbol($0) },
                        parameters: match.node.callGraphParameterEvidence,
                        casePatterns: match.node.casePatternEvidence,
                        path: file.path,
                        component: file.component,
                        location: file.position(of: match.node)
                    )
                )
                localCallees.append(match.node.locallyDispatchedCalleeNames)
            }
        }

        var edges: [[Int]] = Array(repeating: [], count: nodes.count)
        var indexesByName: [String: [Int]] = [:]
        for (index, node) in nodes.enumerated() {
            indexesByName[node.function.name, default: []].append(index)
        }

        for (caller, callees) in localCallees.enumerated() {
            for callee in callees {
                let candidates = (indexesByName[callee] ?? []).filter { candidate in
                    nodes[candidate].enclosingType == nodes[caller].enclosingType
                        || nodes[candidate].enclosingType == nil
                }
                edges[caller].append(contentsOf: candidates)
            }
        }

        let components = stronglyConnectedComponents(count: nodes.count, edges: edges)
        let recursive = components.filter { component in
            component.count > 1 || component.contains { index in
                edges[index].contains(index)
            }
        }

        return RecursiveCallGroups(
            groups: recursive.map { component in
                component.map { index in nodes[index] }
            }
        )
    }
}

private extension FunctionDeclSyntax {
    var callGraphParameterEvidence: [CallGraphParameterEvidence] {
        signature.parameterClause.parameters.compactMap { parameter in
            let localName = parameter.secondName?.text ?? parameter.firstName.text
            guard !StringMatcher.exact("_").matches(localName) else {
                return nil
            }
            return CallGraphParameterEvidence(
                localName: localName,
                typeSpelling: parameter.type.trimmedDescription
            )
        }
    }

    var casePatternEvidence: [CasePatternEvidence] {
        guard let body else {
            return []
        }
        return body.descendants(of: ExpressionPatternSyntax.self).flatMap { pattern -> [CasePatternEvidence] in
            guard let subjectExpression = pattern.matchedSubjectExpression else {
                return []
            }
            return pattern.expression.descendants(of: MemberAccessExprSyntax.self).map { reference in
                CasePatternEvidence(
                    memberName: reference.declName.baseName.text,
                    subjectExpression: subjectExpression
                )
            }
        }
    }
}

private extension ExpressionPatternSyntax {
    var matchedSubjectExpression: String? {
        if let condition = ancestors.compactMap({ ancestor in
            ancestor.as(MatchingPatternConditionSyntax.self)
        }).first {
            return condition.initializer.value.trimmedDescription
        }

        guard ancestors.contains(where: { ancestor in
            ancestor.is(SwitchCaseItemSyntax.self)
        }), let switchExpression = ancestors.compactMap({ ancestor in
            ancestor.as(SwitchExprSyntax.self)
        }).first else {
            return nil
        }
        return switchExpression.subject.trimmedDescription
    }
}

// MARK: - Built-in provider values

extension BuiltInFacts {
    public static let sourceFiles = SourceFileFactsProvider()
    public static let imports = ImportInventoryProvider()
    public static let nominalTypes = NominalTypeInventoryProvider()
    public static let extensions = ExtensionInventoryProvider()
    public static let storedProperties = StoredPropertyInventoryProvider()
    public static let syntaxNodes = SyntaxNodeInventoryProvider()
    public static let effectiveAccess = EffectiveAccessProvider()
    public static let enclosingDeclarations = EnclosingDeclarationsProvider()
    public static let memberReferences = MemberReferenceInventoryProvider()
    public static let componentDependencies = ComponentDependencyProvider()
    public static let recursiveCallGroups = CallGraphSCCProvider()
}

// MARK: - Support

extension AccessLevel {
    /// Broader access ranks higher; used to cap nested declarations.
    var visibilityRank: Int {
        switch self {
        case .private: 0
        case .fileprivate: 1
        case .internal: 2
        case .package: 3
        case .public: 4
        case .open: 5
        }
    }
}

extension DeclSyntax {
    func nominalTypeFacts(location: SourcePosition?) -> NominalType? {
        if let declaration = self.as(StructDeclSyntax.self) {
            return declaration.bumper.nominalType(location: location)
        }
        if let declaration = self.as(ClassDeclSyntax.self) {
            return declaration.bumper.nominalType(location: location)
        }
        if let declaration = self.as(EnumDeclSyntax.self) {
            return declaration.bumper.nominalType(location: location)
        }
        if let declaration = self.as(ActorDeclSyntax.self) {
            return declaration.bumper.nominalType(location: location)
        }
        if let declaration = self.as(ProtocolDeclSyntax.self) {
            return declaration.bumper.nominalType(location: location)
        }
        return nil
    }
}

/// Tarjan's strongly connected components over adjacency lists.
private func stronglyConnectedComponents(count: Int, edges: [[Int]]) -> [[Int]] {
    var index = 0
    var stack: [Int] = []
    var onStack = Array(repeating: false, count: count)
    var indices = Array(repeating: -1, count: count)
    var lowLinks = Array(repeating: 0, count: count)
    var components: [[Int]] = []

    func strongConnect(_ node: Int) {
        indices[node] = index
        lowLinks[node] = index
        index += 1
        stack.append(node)
        onStack[node] = true

        for neighbor in edges[node] {
            if indices[neighbor] == -1 {
                strongConnect(neighbor)
                lowLinks[node] = min(lowLinks[node], lowLinks[neighbor])
            } else if onStack[neighbor] {
                lowLinks[node] = min(lowLinks[node], indices[neighbor])
            }
        }

        if lowLinks[node] == indices[node] {
            var component: [Int] = []
            while let member = stack.popLast() {
                onStack[member] = false
                component.append(member)
                if member == node {
                    break
                }
            }
            components.append(component)
        }
    }

    for node in 0..<count where indices[node] == -1 {
        strongConnect(node)
    }

    return components
}
