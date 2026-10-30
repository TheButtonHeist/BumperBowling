import Foundation
import SwiftSyntax

/// Typed identity for one fact provider.
public struct FactProviderID: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            preconditionFailure("Fact provider IDs cannot be empty.")
        }
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String {
        rawValue
    }
}

/// An extensible, typed, memoized derivation over repository syntax.
/// A provider is evaluated at most once per engine run; dependencies are
/// explicit through `context.facts(...)`. Providers are values, so both
/// named provider structs and closure-backed `DerivedFact`s conform.
/// An ID identifies the complete derivation, including parameters. Providers
/// with the same ID share the first result or error within one run.
public protocol FactProvider: Sendable {
    associatedtype Facts: Sendable

    var id: FactProviderID { get }

    func derive(in context: FactDerivationContext) throws -> Facts
}

/// A closure-backed fact provider: the normal low-boilerplate project API.
public struct DerivedFact<Value: Sendable>: FactProvider {
    public let id: FactProviderID
    private let derivation: @Sendable (FactDerivationContext) throws -> Value

    public init(
        _ id: FactProviderID,
        derive: @escaping @Sendable (FactDerivationContext) throws -> Value
    ) {
        self.id = id
        self.derivation = derive
    }

    public func derive(in context: FactDerivationContext) throws -> Value {
        try derivation(context)
    }
}

public struct FactDerivationContext: Sendable {
    public let repository: RepositorySyntax
    public let configuration: ArchitectureConfiguration
    private let store: FactStore

    init(repository: RepositorySyntax, configuration: ArchitectureConfiguration, store: FactStore) {
        self.repository = repository
        self.configuration = configuration
        self.store = store
    }

    public func facts<Provider: FactProvider>(_ provider: Provider) throws -> Provider.Facts {
        try store.facts(provider, repository: repository, configuration: configuration)
    }
}

public enum FactProviderError: Error, Equatable, Sendable, CustomStringConvertible {
    case dependencyCycle([FactProviderID])
    case factTypeMismatch(FactProviderID)

    public var description: String {
        switch self {
        case .dependencyCycle(let path):
            "Fact provider dependency cycle: \(path.map(\.rawValue).joined(separator: " -> "))"
        case .factTypeMismatch(let id):
            "Fact provider \(id.rawValue) is registered with a different fact type."
        }
    }
}

// ponytail: one recursive lock serializes fact derivation; move to
// per-provider once-cells if derivation becomes the lint bottleneck.
final class FactStore: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var cache: [FactProviderID: Result<any Sendable, Error>] = [:]
    private var derivationPath: [FactProviderID] = []
    private var derivationMeasurements: [EvaluationTelemetry.Measurement] = []

    func facts<Provider: FactProvider>(
        _ provider: Provider,
        repository: RepositorySyntax,
        configuration: ArchitectureConfiguration
    ) throws -> Provider.Facts {
        lock.lock()
        defer { lock.unlock() }

        let id = provider.id
        if let cached = cache[id] {
            return try typedFacts(from: cached.get(), id: id)
        }

        guard !derivationPath.contains(id) else {
            throw FactProviderError.dependencyCycle(derivationPath + [id])
        }

        derivationPath.append(id)
        defer { derivationPath.removeLast() }

        let context = FactDerivationContext(repository: repository, configuration: configuration, store: self)
        let clock = ContinuousClock()
        let start = clock.now
        let result = Result<any Sendable, Error> { try provider.derive(in: context) }
        derivationMeasurements.append(
            EvaluationTelemetry.Measurement(id: id.rawValue, seconds: (clock.now - start).secondsValue)
        )
        cache[id] = result
        return try typedFacts(from: result.get(), id: id)
    }

    func measurements() -> [EvaluationTelemetry.Measurement] {
        lock.lock()
        defer { lock.unlock() }
        return derivationMeasurements
    }

    private func typedFacts<Facts>(from value: any Sendable, id: FactProviderID) throws -> Facts {
        guard let facts = value as? Facts else {
            throw FactProviderError.factTypeMismatch(id)
        }
        return facts
    }
}

// MARK: - Built-in providers

/// Where one nominal declaration lives.
public struct DeclarationOccurrence: Equatable, Sendable {
    public let symbol: NominalSymbol
    public let kind: DeclarationKind?
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(
        symbol: NominalSymbol,
        kind: DeclarationKind?,
        path: RelativeFilePath,
        component: ComponentID?,
        location: SourcePosition?
    ) {
        self.symbol = symbol
        self.kind = kind
        self.path = path
        self.component = component
        self.location = location
    }
}

public struct DeclarationInventory: Sendable {
    public let occurrences: [DeclarationOccurrence]

    public init(occurrences: [DeclarationOccurrence]) {
        self.occurrences = occurrences
    }

    public func occurrences(of symbol: NominalSymbol) -> [DeclarationOccurrence] {
        occurrences.filter { occurrence in
            occurrence.symbol == symbol
        }
    }
}

/// Nominal declarations across the repository.
public struct DeclarationInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.declaration_inventory"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> DeclarationInventory {
        DeclarationInventory(
            occurrences: context.repository.files.flatMap { file in
                nominalDeclarations().matches(in: file).compactMap { match in
                    match.node.nominalDeclaration.map { declaration in
                        DeclarationOccurrence(
                            symbol: NominalSymbol(declaration.name),
                            kind: declaration.kind,
                            path: file.path,
                            component: file.component,
                            location: file.position(of: match.node)
                        )
                    }
                }
            }
        )
    }
}

/// One observed function or initializer call.
public struct FunctionCallOccurrence: Equatable, Sendable {
    public let callee: FunctionSymbol
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(
        callee: FunctionSymbol,
        path: RelativeFilePath,
        component: ComponentID?,
        location: SourcePosition?
    ) {
        self.callee = callee
        self.path = path
        self.component = component
        self.location = location
    }
}

public struct FunctionCallInventory: Sendable {
    public let occurrences: [FunctionCallOccurrence]

    public init(occurrences: [FunctionCallOccurrence]) {
        self.occurrences = occurrences
    }

    public func calls(to symbol: FunctionSymbol) -> [FunctionCallOccurrence] {
        occurrences.filter { occurrence in
            occurrence.callee == symbol
        }
    }
}

/// Function and initializer calls derived from repository syntax.
public struct FunctionCallInventoryProvider: FactProvider {
    public let id: FactProviderID = "bumper.function_call_inventory"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> FunctionCallInventory {
        FunctionCallInventory(
            occurrences: context.repository.files.flatMap { file in
                functionCalls().matches(in: file).map { match in
                    FunctionCallOccurrence(
                        callee: FunctionSymbol(match.node.calleeName),
                        path: file.path,
                        component: file.component,
                        location: file.position(of: match.node)
                    )
                }
            }
        )
    }
}

/// One directly recursive function.
public struct RecursiveFunctionOccurrence: Equatable, Sendable {
    public let function: FunctionSymbol
    public let enclosingType: NominalSymbol?
    public let parameterTypeNames: [String]
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?

    public init(
        function: FunctionSymbol,
        enclosingType: NominalSymbol?,
        parameterTypeNames: [String],
        path: RelativeFilePath,
        component: ComponentID?,
        location: SourcePosition?
    ) {
        self.function = function
        self.enclosingType = enclosingType
        self.parameterTypeNames = parameterTypeNames
        self.path = path
        self.component = component
        self.location = location
    }
}

public struct DirectRecursionInventory: Sendable {
    public let occurrences: [RecursiveFunctionOccurrence]

    public init(occurrences: [RecursiveFunctionOccurrence]) {
        self.occurrences = occurrences
    }
}

/// Canonical built-in provider values, mirroring `Rules` for facts.
public enum BuiltInFacts {
    public static let declarations = DeclarationInventoryProvider()
    public static let functionCalls = FunctionCallInventoryProvider()
    public static let directRecursion = DirectRecursionProvider()
}

// ponytail: direct recursion only; a call-graph SCC provider can add mutual
// recursion later without changing dependent rule contracts.
public struct DirectRecursionProvider: FactProvider {
    public let id: FactProviderID = "bumper.direct_recursion"

    public init() {}

    public func derive(in context: FactDerivationContext) throws -> DirectRecursionInventory {
        DirectRecursionInventory(
            occurrences: context.repository.files.flatMap { file in
                functions().callingSelf().matches(in: file).map { match in
                    RecursiveFunctionOccurrence(
                        function: FunctionSymbol(match.node.name.text),
                        enclosingType: match.node.enclosingNominalName.map { NominalSymbol($0) },
                        parameterTypeNames: match.node.signature.parameterClause.parameters.map { parameter in
                            parameter.type.trimmedDescription
                        },
                        path: file.path,
                        component: file.component,
                        location: file.position(of: match.node)
                    )
                }
            }
        )
    }
}
