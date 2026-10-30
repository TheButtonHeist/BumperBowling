import BumperBowlingCore
import Foundation

/// Evaluates exactly one rule over an in-memory repository and returns the
/// same structured report the engine and CLI use. Framework-neutral: no
/// XCTest or Swift Testing dependency.
public struct RuleTestHarness: Sendable {
    private let rules: RuleSet

    public init(_ rule: some RuleDefinition) {
        self.rules = RuleSet(rules: [rule])
    }

    /// Runs an explicitly supplied rule set instead of one rule.
    public init(_ rules: RuleSet) {
        self.rules = rules
    }

    public func evaluate(_ repository: VirtualRepository) throws -> RuleReport {
        try rules.evaluate(
            configuration: configuration(for: repository),
            repository: RepositorySyntax(
                files: repository.files.map { file in
                    SourceFileContext(
                        descriptor: SourceFileDescriptor(path: file.path, component: file.component),
                        source: file.source
                    )
                }
            )
        )
    }

    private func configuration(for repository: VirtualRepository) -> ArchitectureConfiguration {
        let componentPaths = Dictionary(grouping: repository.files, by: \.component)
        return ArchitectureConfiguration(
            components: componentPaths
                .compactMap { component, files in
                    guard let component else { return nil }
                    return ComponentConfiguration(
                        name: component.rawValue,
                        paths: files.map(\.path.rawValue)
                    )
                }.sorted { $0.name < $1.name }
        )
    }
}
