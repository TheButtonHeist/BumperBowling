import SwiftSyntax
import Testing
@testable import BumperBowlingCore

@Suite("Declaration contracts")
struct DeclarationContractTests {
    @Test func exportedSignaturesIncludeEveryRequestedBoundary() throws {
        let file = try contractFile("""
        public typealias Pair = (Int, Int)
        public struct Example {
            public init(_ pair: (Int, Int)) {}
            public func exchange(_ input: (Int, Int)) -> (Int, Int) { input }
            public private(set) var stored: (Int, Int)
            public var computed: (Int, Int) { (0, 0) }
            public subscript(_ key: (Int, Int)) -> (Int, Int) { key }
        }
        public enum ExampleEnum { case pair((Int, Int)), other(String) }
        """)
        let context = RuleContext(configuration: ArchitectureConfiguration(components: []), repository: RepositorySyntax(files: [file]))
        let contracts = try context.facts(BuiltInFacts.declarationContracts)
        let exported = contracts.filter { $0.effectiveAccess == .resolved(.public) }
        #expect(exported.count == 10)
        let types = exported.flatMap(\.types)
        #expect(types.filter { $0.type.spelling == "(Int, Int)" }.map(\.kind) == [
            .typeAlias, .initializerParameter, .functionParameter, .functionReturn,
            .property, .property, .subscriptParameter, .subscriptReturn, .enumAssociatedValue,
        ])
        #expect(types.filter { $0.syntax.is(TupleTypeSyntax.self) }.count == 9)
        let initializer = try #require(contracts.first { $0.kind == "initializer" })
        #expect(initializer.explicitAccess == .public)
        #expect(initializer.context.enclosingNominalNames == ["Example"])
        #expect(initializer.path.rawValue == "Sources/Core/Fixture.swift")
        #expect(initializer.location.line == 3)
        #expect(initializer.types.first?.location.line == 3)
        #expect(contracts.first { $0.name == "stored" }?.explicitAccess == .public)
        #expect(contracts.first { $0.name == "other" }?.types.map(\.type.spelling) == ["String"])
    }

    @Test func accessInheritsDefaultsAndRespectsEnclosingCaps() throws {
        let file = try contractFile("""
        public protocol Service {
            func call(_ value: (Int, Int)) -> (Int, Int)
            var state: (Int, Int) { get }
            init(_ value: (Int, Int))
            subscript(_ value: Int) -> (Int, Int) { get }
            associatedtype Value
        }
        struct Hidden { public struct Nested { public func hidden() {} } }
        public struct Visible {}
        public extension Visible { func inherited() {} }
        extension Visible { func ordinary() {} }
        public extension Hidden { func capped() {} }
        extension External { public func unknown() {} }
        public class Base { public func work() {} }
        public class Derived: Base { override func work() {} }
        #if FLAG
        public func conditional() {}
        #endif
        """)
        let contracts = file.declarationContracts()
        for name in ["call", "state", "init", "subscript", "Value", "inherited", "conditional"] {
            #expect(contracts.first { $0.name == name }?.effectiveAccess == .resolved(.public))
        }
        for name in ["hidden", "Nested", "ordinary", "capped"] {
            #expect(contracts.first { $0.name == name }?.effectiveAccess == .resolved(.internal))
        }
        #expect(contracts.first { $0.name == "inherited" }?.explicitAccess == nil)
        guard case .unresolved = contracts.first(where: { $0.name == "unknown" })?.effectiveAccess else {
            Issue.record("External extension access must remain unresolved")
            return
        }
        guard case .unresolved = contracts.last(where: { $0.name == "work" })?.effectiveAccess else {
            Issue.record("Overrides require compiler context")
            return
        }
    }

    @Test func sharedPropertyAnnotationsAndLocalDeclarationsStayAccurate() throws {
        let contracts = try contractFile("""
        public struct Example {
            public var first, second: (Int, Int)
            public var inferred = 0, annotated: (Int, Int)
            public func outer() { struct Local { public func inner() {} } }
        }
        """).declarationContracts()
        for name in ["first", "second"] {
            #expect(contracts.first { $0.name == name }?.types.first?.type.spelling == "(Int, Int)")
        }
        #expect(contracts.first { $0.name == "inferred" }?.types.isEmpty == true)
        #expect(contracts.first { $0.name == "inner" }?.effectiveAccess == .resolved(.private))
    }
}

private func contractFile(_ source: String) throws -> SourceFileContext {
    try SourceFileContext(descriptor: SourceFileDescriptor(path: "Sources/Core/Fixture.swift", component: ComponentID("core")), source: source)
}
