import Foundation

/// The bounded, Codable source snapshot the host sends to the project
/// runner's `evaluate` mode. The host owns filesystem safety, inclusion,
/// exclusion, size limits, and sandboxing; the runner owns parsing.
public struct RepositoryInput: Equatable, Sendable, Codable {
    public let architecture: ArchitectureConfiguration
    public let files: [SourceInput]
    public let coverage: SourceCoverageSummary?

    public init(architecture: ArchitectureConfiguration = ArchitectureConfiguration(), files: [SourceInput], coverage: SourceCoverageSummary? = nil) {
        self.architecture = architecture
        self.coverage = coverage
        self.files = files
    }
}

/// One raw source file crossing the host/runner boundary.
public struct SourceInput: Equatable, Sendable, Codable {
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let source: String

    public init(path: RelativeFilePath, component: ComponentID? = nil, source: String) {
        self.path = path
        self.component = component
        self.source = source
    }
}

/// The immutable parsed repository: every file's source parsed exactly once.
public struct RepositorySyntax: Sendable {
    public let files: [SourceFileContext]
    public let coverage: SourceCoverageSummary?

    public init(files: [SourceFileContext], coverage: SourceCoverageSummary? = nil) {
        self.coverage = coverage
        self.files = files
    }

    /// Parses each source input exactly once.
    public init(input: RepositoryInput) {
        self.init(
            files: input.files.map { file in
                SourceFileContext(
                    descriptor: SourceFileDescriptor(path: file.path, component: file.component),
                    source: file.source
                )
            },
            coverage: input.coverage
        )
    }

    /// Builds the parsed repository from scanned facts. Missing source text
    /// is an explicit analysis failure, not an empty match set.
    public init(facts: RepositoryFacts) throws {
        self.init(files: try facts.files.map(SourceFileContext.init), coverage: facts.coverage)
    }
}

/// Typed path, component, and other cheap per-file metadata that does not
/// duplicate syntax facts.
public struct SourceFileDescriptor: Equatable, Hashable, Sendable, Codable {
    public let path: RelativeFilePath
    /// Optional architecture metadata. Unowned sources remain available to rules.
    public let component: ComponentID?

    public init(path: RelativeFilePath, component: ComponentID? = nil) {
        self.path = path
        self.component = component
    }
}

/// Immutable repository, file, configuration, and fact access for one
/// evaluation run. Only the engine constructs a context, which guarantees
/// one repository and one fact cache per run.
public final class RuleContext: Sendable {
    public let configuration: ArchitectureConfiguration
    public let repository: RepositorySyntax
    private let factStore: FactStore

    init(configuration: ArchitectureConfiguration, repository: RepositorySyntax) {
        self.configuration = configuration
        self.repository = repository
        self.factStore = FactStore()
    }

    public func files(in scope: RuleScope) -> [SourceFileContext] {
        repository.files.filter { file in
            scope.includes(file)
        }
    }

    public func facts<Provider: FactProvider>(_ provider: Provider) throws -> Provider.Facts {
        try factStore.facts(provider, repository: repository, configuration: configuration)
    }

    func factMeasurements() -> [EvaluationTelemetry.Measurement] {
        factStore.measurements()
    }
}
