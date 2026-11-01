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

private func typeContext(_ source: String) -> SourceFileContext {
    SourceFileContext(file: SwiftLintFile(contents: source), root: FileManager.default.temporaryDirectory)
}
