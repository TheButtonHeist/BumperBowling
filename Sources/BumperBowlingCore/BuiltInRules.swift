import Foundation

/// The architecture graph and compiled rules, derived once per run so every
/// built-in rule shares one graph.
struct ArchitectureEvaluationFacts: Sendable {
    let graph: ArchitectureGraph
    let rules: ArchitectureRules
}

struct ArchitectureEvaluationProvider: FactProvider {
    let id: FactProviderID = "bumper.architecture_graph"

    func derive(in context: FactDerivationContext) throws -> ArchitectureEvaluationFacts {
        let rules = try ArchitectureRules(configuration: context.configuration)
        let files = try context.facts(BuiltInFacts.sourceFiles)
        return ArchitectureEvaluationFacts(
            graph: ArchitectureGraph(nodes: RepositoryFacts(files: files, coverage: context.repository.coverage), rules: rules),
            rules: rules
        )
    }
}

let architectureEvaluationFacts = ArchitectureEvaluationProvider()

/// One built-in rule family as an ordinary `RuleDefinition`. Scoped settings
/// evaluate inside the family and report per-setting severities under one
/// stable rule ID, so one project cannot declare the same ID twice.
struct BuiltInRule: RuleDefinition {
    let metadata: RuleMetadata
    private let family: [ArchitectureRule]

    init?(family: [ArchitectureRule]) {
        let enabled = family.filter(\.isEnabled)
        guard let first = enabled.first else {
            return nil
        }
        self.metadata = RuleMetadata(
            id: first.id,
            severity: enabled.map(\.configuredSeverity).reduce(.off) { merged, severity in
                merged.merging(severity)
            },
            summary: first.description
        )
        self.family = enabled
    }

    var scope: RuleScope {
        .repository
    }

    func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        if metadata.id == .sourceCoverage, context.repository.coverage == nil {
            throw RuleEvaluationError.ruleFailed(.sourceCoverage, "Source inventory is missing. Use RepositoryScanner.scanInput(root:) or scan(root:) to evaluate coverage.")
        }
        let facts = try context.facts(architectureEvaluationFacts)
        return family.flatMap { rule in
            rule.evaluate(graph: facts.graph, rules: facts.rules)
        }
    }
}

/// Built-in architecture rules over the one open engine: ordinary rule
/// definitions built from wire configuration, with no privileged semantics.
enum BuiltInRules {
    static func families(from configuration: RuleConfiguration) -> [[ArchitectureRule]] {
        [
            [.forbiddenImport(configuration.forbiddenImports)],
            [.componentBoundary(configuration.componentBoundary)],
            [.duplicateOwnership(configuration.duplicateOwnership)],
            [.sourceCoverage(configuration.sourceCoverage ?? .off)],
            [.declaredDependencyCycle(configuration.declaredDependencyCycle)],
            configuration.storedPropertyRules.map(ArchitectureRule.storedProperties),
            configuration.syntaxConstructRules.map(ArchitectureRule.syntaxConstructs),
            configuration.syntaxKindRules.map(ArchitectureRule.syntaxKinds),
            configuration.syntaxNodeRules.map(ArchitectureRule.syntaxNodes),
            configuration.publicDeclarationRules.map(ArchitectureRule.publicDeclarations),
            configuration.enumStateMachineRules.map(ArchitectureRule.enumStateMachine),
        ]
    }

    static func rules(from configuration: RuleConfiguration) -> [any RuleDefinition] {
        families(from: configuration).compactMap(BuiltInRule.init)
    }

    static func ruleSet(from configuration: ArchitectureConfiguration) -> RuleSet {
        RuleSet(rules: rules(from: configuration.rules))
    }
}
