import BumperBowlingCore
import Foundation
import SwiftLintFramework
import SwiftSyntax
import Testing

@Test func explicitContractTypesIncludeEveryExportedDeclarationForm() {
    let file = declarationContext("""
    public typealias Pair = (Int, Int)
    public struct Sample {
        public init(_ pair: (Int, Int)) {}
        public func transform(_ pair: (Int, Int)) -> [(Int, Int)] { [] }
        public private(set) var pair: (Int, Int) = (0, 0)
        public subscript(_ pair: (Int, Int)) -> (Int, Int) { pair }
    }
    public enum Payload { case pair((Int, Int)); case named(left: Int, right: Int) }
    public protocol Contract { associatedtype Pair = (Int, Int) }
    """)
    let declarations = SyntaxQuery<DeclSyntax>().matches(in: file)
    let tupleTypes = declarations.flatMap { $0.node.contractTypes }.flatMap { $0.descendants(of: TupleTypeSyntax.self) }.filter { $0.elements.count > 1 }
    #expect(tupleTypes.count == 9)
    #expect(declarations.filter { $0.node.as(VariableDeclSyntax.self) != nil }.first?.node.explicitAccess == .public)
    #expect(declarations.filter { !$0.node.contractTypes.isEmpty }.allSatisfy { $0.node.effectiveAccess == .resolved(.public) })
}

@Test func accessDefaultsCapsAndLocalScratchRemainExplicit() {
    let file = declarationContext("""
    public protocol Contract { func requirement() }
    struct Hidden { public func capped() {} }
    public struct Visible { func internalDefault() {} }
    public extension Visible { func inherited() {}; private func helper() {} }
    package extension Visible { func packageDefault() {} }
    func local() { struct Local { public func scratch() {} } }
    public class Base { public func overridePoint() {} }
    public class Child: Base { override func overridePoint() {} }
    extension Imported { public func unknown() {} }
    """)
    let expected: [String: LexicalAccess] = [
        "requirement": .resolved(.public), "capped": .resolved(.internal), "internalDefault": .resolved(.internal),
        "inherited": .resolved(.public), "helper": .resolved(.private), "packageDefault": .resolved(.package),
        "local": .resolved(.internal), "scratch": .resolved(.private), "unknown": .unresolved,
    ]
    for function in functions().matches(in: file) {
        if function.name == "overridePoint" { continue }
        #expect(function.node.effectiveAccess == expected[function.name])
    }
    #expect(functions().matches(in: file).filter { $0.name == "overridePoint" }.map { $0.node.effectiveAccess } == [.resolved(.public), .unresolved])
}

@Test func privateExtensionDefaultsDoNotCapExplicitMembers() {
    let file = declarationContext("""
    public struct Visible {}
    private extension Visible { public func exported() {}; func helper() {} }
    private struct Hidden {}
    extension Hidden { public func capped() {} }
    """)
    #expect(functions().matches(in: file).map { $0.node.effectiveAccess } == [.resolved(.public), .resolved(.private), .resolved(.private)])
}

@Test func qualifiedExtensionAccessIgnoresTriviaAndKeepsUnknownTargetsUnresolved() {
    let file = declarationContext("""
    public enum Outer { public struct Inner {} }
    public extension Outer . Inner { func exported() {} }
    extension Library.Imported { public func unknown() {} }
    """)
    #expect(functions().matches(in: file).map { $0.node.effectiveAccess } == [.resolved(.public), .unresolved])
}

@Test(arguments: [
    "func scratch() { enum Outer { struct Model {} } }",
    "let scratch = { enum Outer { struct Model {} } }",
])
func extensionAccessIgnoresFunctionAndClosureLocalTypes(local: String) throws {
    let file = declarationContext("""
    public enum Outer { public struct Model {} }
    extension Outer.Model { public func value() -> Int { 0 } }
    \(local)
    """)
    let method = try #require(functions().matches(in: file).first { $0.name == "value" })
    #expect(method.node.effectiveAccess == .resolved(.public))
}

private func declarationContext(_ source: String) -> SourceFileContext {
    SourceFileContext(file: SwiftLintFile(contents: source), root: FileManager.default.temporaryDirectory)
}
