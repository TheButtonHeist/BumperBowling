extension Array where Element == RuleConfiguration {
    func combined() -> RuleConfiguration {
        reduce(RuleConfiguration()) { partialResult, configuration in
            partialResult.merging(configuration)
        }
    }
}
extension RuleConfiguration {
    func merging(_ other: RuleConfiguration) -> RuleConfiguration {
        RuleConfiguration(
            forbiddenImports: forbiddenImports + other.forbiddenImports,
            componentBoundary: other.componentBoundary.isConfigured ? other.componentBoundary : componentBoundary,
            duplicateOwnership: other.duplicateOwnership.isConfigured ? other.duplicateOwnership : duplicateOwnership,
            sourceCoverage: other.sourceCoverage ?? sourceCoverage,
            declaredDependencyCycle: other.declaredDependencyCycle.isConfigured
                ? other.declaredDependencyCycle
                : declaredDependencyCycle,
            storedPropertyRules: storedPropertyRules + other.storedPropertyRules,
            syntaxConstructRules: syntaxConstructRules + other.syntaxConstructRules,
            syntaxKindRules: syntaxKindRules + other.syntaxKindRules,
            syntaxNodeRules: syntaxNodeRules + other.syntaxNodeRules,
            publicDeclarationRules: publicDeclarationRules + other.publicDeclarationRules,
            enumStateMachineRules: enumStateMachineRules + other.enumStateMachineRules
        )
    }
}

private extension Severity {
    var isConfigured: Bool {
        self != .off
    }
}
