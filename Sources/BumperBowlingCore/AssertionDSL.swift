public struct AssertionShape: Equatable, Sendable {
    public let configuration: RuleConfiguration

    public init(configuration: RuleConfiguration) {
        self.configuration = configuration
    }

    public init(@AssertionsBuilder _ content: () -> [RuleConfiguration]) {
        self.configuration = content().combined()
    }
}
public func NoDirectStringMatching(
    _ severity: Severity,
    paths: [String],
    except excludedPaths: [String] = []
) -> RuleConfiguration {
    RuleConfiguration(
        syntaxConstructs: SyntaxConstructRuleConfiguration(
            severity: severity,
            paths: paths,
            excludedPaths: excludedPaths,
            disallowedConstructs: [.directStringMatch]
        )
    )
}

public func ApplyAssertions(_ shape: AssertionShape) -> RuleConfiguration {
    shape.configuration
}

@resultBuilder
public enum AssertionsBuilder {
    public static func buildBlock(_ components: RuleConfiguration...) -> [RuleConfiguration] {
        components
    }
}

public func DependencyBoundaries(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(componentBoundary: severity)
}

public func SingleOwner(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(duplicateOwnership: severity)
}

public func SourceCoverage(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(sourceCoverage: severity)
}

public func AcyclicDeclaredDependencies(_ severity: Severity) -> RuleConfiguration {
    RuleConfiguration(declaredDependencyCycle: severity)
}
