import SwiftSyntax
import Testing
@testable import BumperBowlingCore

@Suite("Lexical type resolution")
struct LexicalTypeResolverTests {
    @Test func callbackAliasesPreserveOuterAttributesAcrossWrappers() throws {
        let file = try lexicalFile("""
        @globalActor actor UIExecutor { static let shared = UIExecutor() }
        typealias First = @UIExecutor @Sendable () -> Void
        typealias Second = First
        final class Example {
            var onChange: Second?
            var genericOptional: Optional<Second>
            var qualifiedOptional: Swift.Optional<Second>
            var attributed: (@UIExecutor Second)?
            var nested: (@UIExecutor () -> Void) -> Void
        }
        """)
        let resolver = LexicalTypeResolver(file: file)
        for name in ["onChange", "genericOptional", "qualifiedOptional", "attributed"] {
            let type = try propertyType(name, file: file)
            let result = resolver.resolve(type)
            #expect(result.failure == nil)
            #expect(result.aliasChain == ["Second", "First"])
            #expect(result.type.isFunction)
            #expect(result.type.outerFunctionAttributes == ["UIExecutor", "Sendable"])
            let actor = try #require(result.outerFunctionAttributes.first { $0.name == "UIExecutor" })
            #expect(actor.globalActorLocation?.line == 1)
            #expect(actor.failure == nil)
        }
        let nested = resolver.resolve(try propertyType("nested", file: file))
        #expect(nested.type.outerFunctionAttributes.isEmpty)
        #expect(nested.outerFunctionAttributes.isEmpty)
    }

    @Test func nearestScopeWinsAndUnknownIdentityIsExplicit() throws {
        let file = try lexicalFile("""
        typealias Callback = @Sendable () -> Void
        struct Outer {
            typealias Callback = @UIExecutor () -> Void
            var member: Callback
            func run() {
                typealias Callback = () -> Int
                let local: Callback
            }
        }
        struct Generic<Callback> { var generic: Callback }
        func genericParameter<Callback>(_ parameter: Callback) {}
        func forwardReference() {
            let forward: Callback
            typealias Callback = () -> String
        }
        protocol Service { associatedtype Callback; var associated: Callback { get } }
        struct Unknown { var imported: OtherFileAlias; var qualified: Other.Callback }
        """)
        let resolver = LexicalTypeResolver(file: file)
        let member = resolver.resolve(try propertyType("member", file: file))
        #expect(member.type.outerFunctionAttributes == ["UIExecutor"])
        #expect(member.outerFunctionAttributes.first?.failure == .unknownName("UIExecutor"))
        let local = resolver.resolve(try propertyType("local", file: file))
        #expect(local.type.spelling == "() -> Int")
        #expect(local.type.outerFunctionAttributes.isEmpty)
        #expect(resolver.resolve(try propertyType("generic", file: file)).failure == .unknownName("Callback"))
        let genericFunction = try #require(functions().matches(in: file).first { $0.node.name.text == "genericParameter" })
        let parameter = try #require(genericFunction.node.signature.parameterClause.parameters.first)
        #expect(resolver.resolve(parameter.type).failure == .unknownName("Callback"))
        #expect(resolver.resolve(try propertyType("forward", file: file)).type.spelling == "() -> String")
        #expect(resolver.resolve(try propertyType("associated", file: file)).failure == .unsupported("Associated type resolution"))
        #expect(resolver.resolve(try propertyType("imported", file: file)).failure == .unknownName("OtherFileAlias"))
        #expect(resolver.resolve(try propertyType("qualified", file: file)).failure == .unsupported("Other.Callback"))
    }

    @Test func cyclesDepthAndUnsupportedSubstitutionsAreBounded() throws {
        let file = try lexicalFile("""
        typealias A = B
        typealias B = A
        typealias First = () -> Void
        typealias Second = First
        typealias Generic<T> = (T) -> Void
        #if FLAG
        typealias Ambiguous = () -> Void
        #else
        typealias Ambiguous = () -> Int
        #endif
        struct Example { var cycle: A; var depth: Second; var generic: Generic<Int>; var ambiguous: Ambiguous }
        """)
        let resolver = LexicalTypeResolver(file: file)
        #expect(resolver.resolve(try propertyType("cycle", file: file)).failure == .cycle(["A", "B", "A"]))
        #expect(resolver.resolve(try propertyType("depth", file: file), maximumAliasDepth: 1).failure == .depthLimit(1))
        #expect(resolver.resolve(try propertyType("generic", file: file)).failure == .unsupported("Generic alias substitution"))
        #expect(resolver.resolve(try propertyType("ambiguous", file: file)).failure == .ambiguousName("Ambiguous"))
    }

    @Test func actorFactsUseDeclarationsRatherThanNameSuffixes() throws {
        let file = try lexicalFile("""
        @globalActor actor UIExecutor { static let shared = UIExecutor() }
        typealias UI = UIExecutor
        struct NotAnActor {}
        struct Example {
            var valid: @UI () -> Void
            var unknown: @MissingActor () -> Void
            var ordinary: @NotAnActor () -> Void
        }
        """)
        let resolver = LexicalTypeResolver(file: file)
        let valid = resolver.resolve(try propertyType("valid", file: file))
        #expect(valid.outerFunctionAttributes.first?.globalActorLocation?.line == 1)
        #expect(valid.outerFunctionAttributes.first?.name == "UI")
        #expect(resolver.resolve(try propertyType("unknown", file: file)).outerFunctionAttributes.first?.failure == .unknownName("MissingActor"))
        #expect(resolver.resolve(try propertyType("ordinary", file: file)).outerFunctionAttributes.first?.globalActorLocation == nil)
    }
}

private func propertyType(_ name: String, file: SourceFileContext) throws -> TypeSyntax {
    let binding = try #require(variables().matches(in: file).flatMap { $0.node.bindings }.first {
        $0.bumper.identifierName == name
    })
    return try #require(binding.typeAnnotation?.type)
}

private func lexicalFile(_ source: String) throws -> SourceFileContext {
    try SourceFileContext(descriptor: SourceFileDescriptor(path: "Sources/Core/Fixture.swift", component: ComponentID("core")), source: source)
}
