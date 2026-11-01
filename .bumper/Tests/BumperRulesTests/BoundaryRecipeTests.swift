import BumperBowlingCore
import BumperBowlingTestSupport
import BumperRules
import Testing

@Test func migrationRecipesPreserveImportAndOwnershipConventions() throws {
    let harness = RuleTestHarness { NetworkBoundaryRecipe.self; SourceOwnersRecipe.self }
    #expect(try harness.evaluate([
        .swift("Sources/Transport/Socket.swift", source: "import Network"),
        .swift("Sources/TLS.swift", source: "import Network"),
        .swift("Sources/Domain/Model.swift", source: "import Foundation"),
    ]).isEmpty)
    let failing = try harness.evaluate([
        .swift("Sources/Domain/Model.swift", source: "import Network"),
        .swift("Sources/New/Unowned.swift", source: ""),
    ])
    #expect(failing.count == 2)
    #expect(failing.filter(ViolationMatcher(
        id: "recipes.network", path: "Sources/Domain/Model.swift", line: 1, column: 1,
        reason: "Import Network is outside its allowed boundary. Allowed locations: (at or under \"Sources/Transport\") or (\"Sources/TLS.swift\"). Move the code that needs this import to an allowed location."
    ).matches).count == 1)
    #expect(failing.filter(ViolationMatcher(
        id: "recipes.owners", path: "Sources/New/Unowned.swift", line: 1, column: 1,
        reason: "This file has no source owner. Owner scopes: at or under \"Sources/Domain\", at or under \"Sources/Transport\", \"Sources/TLS.swift\". Move the file into an owner scope or add its intended owner."
    ).matches).count == 1)
}

@Test func namedContractsCoverExportedFormsAndPermitScratchValues() throws {
    let harness = RuleTestHarness(NamedContractsRecipe.self)
    #expect(try harness.evaluate([.swift("Sources/Valid.swift", source: """
    public struct Result { public let value: Int; public let ordinal: Int }
    public func operation() -> Result { Result(value: 0, ordinal: 0) }
    private func scratch() -> (Int, Int) { (0, 0) }
    """)]).isEmpty)
    let cases = [
        "public typealias Pair = (Int, Int)",
        "public func operation(_ pair: (Int, Int)) {}",
        "public struct Sample { public init(_ pair: (Int, Int)) {} }",
        "public struct Sample { public private(set) var pair: (Int, Int) = (0, 0) }",
        "public struct Sample { public subscript(index: Int) -> (Int, Int) { (0, 0) } }",
        "public protocol Sample { func operation() -> (Int, Int) }",
        "public protocol Sample { associatedtype Pair = (Int, Int) }",
        "public enum Sample { case pair((Int, Int)) }",
        "public struct Sample {}; public extension Sample { var pair: (Int, Int) { (0, 0) } }",
    ]
    for source in cases {
        let findings = try harness.evaluate([.swift("Sources/Invalid.swift", source: source)])
        #expect(findings.count == 1)
        #expect(findings.first?.reason == "Use a named type in this exported contract.")
    }
    let exact = try harness.evaluate([.swift("Sources/Invalid.swift", source: "public typealias Pair = (Int, Int)")])
    #expect(exact.filter(ViolationMatcher(
        id: "recipes.contracts", path: "Sources/Invalid.swift", line: 1, column: 1,
        reason: "Use a named type in this exported contract."
    ).matches).count == 1)
    let unresolved = try harness.evaluate([.swift("Sources/Extension.swift", source: "extension Imported { public func pair() -> (Int, Int) { (0, 0) } }")])
    #expect(unresolved.count == 1)
    #expect(unresolved.first?.reason == "Access is unresolved. Keep the target declaration in this file or explicitly exclude this boundary.")
}

@Test func callbackRecipeUsesOuterAttributesAndSameFileAliasFacts() throws {
    let harness = RuleTestHarness(CallbackIsolationRecipe.self)
    #expect(try harness.evaluate([.swift("Sources/Valid.swift", source: """
    @globalActor actor UIExecutor { static let shared = UIExecutor() }
    typealias Handler = @UIExecutor () -> Void
    struct Checked { var completion: Handler?; var send: (@Sendable () -> Void)?; let dependency: () -> Void }
    struct Imported { var completion: ImportedHandler? }
    """)]).isEmpty)
    let failing = try harness.evaluate([.swift("Sources/Invalid.swift", source: """
    struct Outer { typealias Handler = () -> Void }
    struct Unchecked {
        var completion: Outer.Handler?
        var onEvent: (@Sendable () -> Void) -> Void
    }
    """)])
    #expect(failing.count == 2)
    for line in [3, 4] {
        #expect(failing.filter(ViolationMatcher(
            id: "recipes.callbacks", path: "Sources/Invalid.swift", line: line, column: 9,
            reason: "Declare @Sendable or a known global actor on the callback type."
        ).matches).count == 1)
    }
}
