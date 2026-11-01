import BumperBowlingCore
import Foundation
import SwiftLintFramework
import SwiftSyntax
import Testing

@Test func callbackFactsKeepOuterIsolationAndOptionalAliases() throws {
    let file = typeContext("""
    @globalActor actor UIExecutor { static let shared = UIExecutor() }
    typealias Executor = UIExecutor
    typealias Checked = @Executor @Sendable (String) -> Void
    typealias Handler = Checked?
    struct Callbacks {
        var first: Handler
        var second: Swift.Optional<Checked>
        var third: Optional<Checked>
        var fourth: ((@Sendable () -> Void) -> Void)?
    }
    """)
    let types = variables().matches(in: file).flatMap { $0.node.contractTypes }
    #expect(types.count == 4)
    for type in types.prefix(3) {
        guard case .resolved(let callback) = file.resolveType(type) else { Issue.record("Expected a callback"); continue }
        #expect(callback.function != nil)
        #expect(callback.isOptional)
        #expect(callback.attributes.map { $0.attributeName.trimmedDescription } == ["Executor", "Sendable"])
        let actor = try #require(callback.attributes.first)
        guard case .resolved(let executor) = file.resolveType(actor.attributeName) else { Issue.record("Expected a same-file actor"); continue }
        #expect(executor.isGlobalActor)
    }
    guard case .resolved(let outer) = file.resolveType(try #require(types.last)) else { Issue.record("Expected outer callback"); return }
    #expect(outer.isOptional)
    #expect(outer.attributes.isEmpty)
}

@Test func aliasesUseTheNearestTypeScopeAndIgnoreValueNames() throws {
    let file = typeContext("""
    typealias Handler = @Sendable () -> Void
    struct Outer {
        typealias Handler = () -> Void
        typealias Chained = Handler
        struct Inner { var completion: Chained? }
    }
    struct Other { var completion: Outer.Chained? }
    struct Values { var Handler = 0; var completion: Handler? }
    func local() { typealias Handler = () -> Void; let completion: Handler? = nil }
    """)
    let types = variables().matches(in: file).flatMap { $0.node.contractTypes }
    for (index, type) in types.enumerated() {
        guard case .resolved(let callback) = file.resolveType(type) else { Issue.record("Expected callback \(index)"); continue }
        #expect(callback.function != nil)
        #expect(callback.isOptional)
        #expect(callback.attributes.isEmpty == (index != 2))
    }
    #expect(types.count == 4)
}

@Test func unresolvedTypesRetainTheirFailureInsteadOfGuessing() throws {
    let examples: [(String, LexicalTypeFailure)] = [
        ("struct Box<Handler> { var callback: Handler? }", .genericParameter("Handler")),
        ("var callback: ImportedHandler?", .unknownName("ImportedHandler")),
        ("var callback: Library.Handler?", .unknownName("Library")),
        ("typealias Handler<T> = (T) -> Void; var callback: Handler<Int>?", .unsupportedSyntax),
        ("typealias First = Second; typealias Second = First; var callback: First?", .cycle),
        ("struct Owner { typealias Handler = Owner.Handler }; var callback: Owner.Handler?", .cycle),
        ("struct Owner { typealias Handler = Alias }; typealias Alias = Owner.Handler; var callback: Alias?", .cycle),
        ("#if FLAG\ntypealias Handler = () -> Void\n#else\ntypealias Handler = @Sendable () -> Void\n#endif\nvar callback: Handler?", .ambiguousName("Handler")),
        ("protocol Box { associatedtype Handler; var callback: Handler? { get } }", .unsupportedSyntax),
    ]
    for (source, expected) in examples {
        let file = typeContext(source)
        let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
        guard case .unresolved(let failure) = file.resolveType(type) else { Issue.record("Unexpected resolution: \(source)"); continue }
        #expect(failure == expected)
    }
}

@Test func depthLimitsIncludeQualifiedOwnerAliasesAndForeignSyntax() throws {
    let file = typeContext("""
    struct Owner { typealias Handler = () -> Void }
    typealias Alias = Owner
    var callback: Alias.Handler?
    """)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .unresolved(.depthLimit) = file.resolveType(type, maximumAliasDepth: 1) else { Issue.record("Owner aliases consume depth"); return }
    guard case .resolved(let resolved) = file.resolveType(type, maximumAliasDepth: 2) else { Issue.record("Expected two aliases"); return }
    #expect(resolved.aliases.map { $0.name.text } == ["Alias", "Handler"])
    let other = typeContext("var callback: (() -> Void)?")
    guard case .unresolved(.foreignSyntax) = other.resolveType(type) else { Issue.record("Foreign tree was accepted"); return }
}

@Test func shadowedOptionalAndActorSuffixesDoNotSupplyFacts() throws {
    let file = typeContext("""
    struct Optional<T> {}
    struct PretendActor {}
    var callback: Optional<() -> Void>
    var plain: (@PretendActor () -> Void)?
    """)
    let types = variables().matches(in: file).flatMap { $0.node.contractTypes }
    guard case .unresolved(.unsupportedSyntax) = file.resolveType(try #require(types.first)) else { Issue.record("Shadowed Optional was unwrapped"); return }
    guard case .resolved(let callback) = file.resolveType(try #require(types.last)) else { Issue.record("Expected function"); return }
    let attribute = try #require(callback.attributes.first)
    guard case .resolved(let actor) = file.resolveType(attribute.attributeName) else { Issue.record("Expected named struct"); return }
    #expect(!actor.isGlobalActor)
}

@Test func aLocalSwiftNamespaceDoesNotBecomeTheStandardOptional() throws {
    let file = typeContext("enum Swift { struct Optional<T> {} }; var callback: Swift.Optional<() -> Void>")
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .unresolved(.unsupportedSyntax) = file.resolveType(type) else { Issue.record("Shadowed Swift.Optional was unwrapped"); return }
}

@Test(arguments: [40, 300])
func optionalWrappersUseABoundedLoop(count: Int) throws {
    let file = typeContext("var callback: (() -> Void)" + String(repeating: "?", count: count))
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    if count < 256 {
        guard case .resolved(let resolved) = file.resolveType(type) else { Issue.record("Expected an optional callback"); return }
        #expect(resolved.isOptional)
        #expect(resolved.function != nil)
    } else {
        guard case .unresolved(.depthLimit) = file.resolveType(type) else { Issue.record("Expected the resolution step limit"); return }
    }
}

@Test func qualifiedOwnerDepthHasItsOwnBound() throws {
    let source = "struct Owner { typealias Next = Owner; typealias Handler = () -> Void }\nvar callback: Owner."
        + String(repeating: "Next.", count: 40) + "Handler?"
    let file = typeContext(source)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .unresolved(.depthLimit) = file.resolveType(type) else { Issue.record("Expected the qualified owner limit"); return }
}

@Test func extensionGenericParametersShadowFileAliases() throws {
    let examples: [(String, LexicalTypeFailure?)] = [
        ("struct Box<Handler> {}; extension Box { var completion: Handler? { nil } }", .genericParameter("Handler")),
        ("struct Outer<Handler> { struct Box {} }; extension Outer.Box { var completion: Handler? { nil } }", .genericParameter("Handler")),
        ("extension Imported { var completion: Handler? { nil } }", .unsupportedSyntax),
        ("struct Box {}; extension Box { var completion: Handler? { nil } }", nil),
    ]
    for (source, expected) in examples {
        let file = typeContext("typealias Handler = () -> Void\n" + source)
        let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
        if let expected {
            guard case .unresolved(let failure) = file.resolveType(type) else { Issue.record("Unexpected resolution: \(source)"); continue }
            #expect(failure == expected)
        } else {
            guard case .resolved(let callback) = file.resolveType(type) else { Issue.record("Expected the file alias"); continue }
            #expect(callback.function != nil)
            #expect(callback.isOptional)
        }
    }
}

@Test func repeatedQualifiedOwnerAliasesAreNotCycles() throws {
    let file = typeContext("""
    struct Owner { typealias Next = Owner; typealias Handler = () -> Void }
    var completion: Owner.Next.Next.Handler?
    """)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .resolved(let callback) = file.resolveType(type) else { Issue.record("Expected a callback through reused owner aliases"); return }
    #expect(callback.function != nil)
    #expect(callback.isOptional)
    #expect(callback.aliases.map { $0.name.text } == ["Next", "Next", "Handler"])
    guard case .unresolved(.depthLimit) = file.resolveType(type, maximumAliasDepth: 2) else { Issue.record("Repeated aliases must consume depth"); return }
}

@Test(arguments: [false, true])
func extensionMemberAliasesShadowFileAliases(isolated: Bool) throws {
    let file = typeContext("""
    typealias Handler = \(isolated ? "" : "@Sendable ")() -> Void
    struct Box { typealias Handler = \(isolated ? "@Sendable " : "")() -> Void }
    extension Box { var completion: Handler? { nil } }
    """)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .resolved(let callback) = file.resolveType(type) else { Issue.record("Expected the member alias"); return }
    #expect(callback.function != nil)
    #expect(callback.isOptional)
    #expect(callback.attributes.map { $0.attributeName.trimmedDescription } == (isolated ? ["Sendable"] : []))
    #expect(callback.aliases.first?.enclosingNominalNames == ["Box"])
}

@Test func nestedExtensionScopesUseMembersBeforeOuterGenericsAndFileAliases() throws {
    let file = typeContext("""
    typealias Handler = () -> Void
    struct Outer<Handler> { struct Box { typealias Handler = @Sendable () -> Void } }
    extension Outer.Box { var completion: Handler? { nil } }
    """)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .resolved(let callback) = file.resolveType(type) else { Issue.record("Expected the nearest member alias"); return }
    #expect(callback.attributes.map { $0.attributeName.trimmedDescription } == ["Sendable"])
}

@Test func enclosingExtensionTargetsStillContributeTheirGenericParameters() throws {
    let file = typeContext("""
    typealias Handler = () -> Void
    struct Outer<Handler> {}
    extension Outer { struct Box {} }
    extension Outer.Box { var completion: Handler? { nil } }
    """)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .unresolved(.genericParameter("Handler")) = file.resolveType(type) else { Issue.record("Expected the outer generic parameter"); return }
}

@Test func aliasesFromOtherExtensionsDoNotFallBackToTheFileAlias() throws {
    let file = typeContext("""
    typealias Handler = @Sendable () -> Void
    struct Box {}
    extension Box { typealias Handler = () -> Void }
    extension Box { var completion: Handler? { nil } }
    """)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .unresolved(.unsupportedSyntax) = file.resolveType(type) else { Issue.record("Another extension can shadow the file alias"); return }
}

@Test func aliasesDeclaredInTheCurrentExtensionKeepTheirPrecedence() throws {
    let file = typeContext("""
    typealias Handler = () -> Void
    struct Box {}
    extension Box {
        typealias Handler = @Sendable () -> Void
        var completion: Handler? { nil }
    }
    """)
    let type = try #require(variables().matches(in: file).flatMap { $0.node.contractTypes }.last)
    guard case .resolved(let callback) = file.resolveType(type) else { Issue.record("Expected this extension's own alias"); return }
    #expect(callback.attributes.map { $0.attributeName.trimmedDescription } == ["Sendable"])
}

private func typeContext(_ source: String) -> SourceFileContext {
    SourceFileContext(file: SwiftLintFile(contents: source), root: FileManager.default.temporaryDirectory)
}
