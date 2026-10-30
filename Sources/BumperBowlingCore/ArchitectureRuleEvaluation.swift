import Foundation
import SwiftSyntax

extension ArchitectureRule {
    func evaluateForbiddenImports(graph: ArchitectureGraph, settings: [RuleSetting]) -> [RuleFailure] {
        settings.flatMap { setting in
            let forbiddenImports = Set((try? setting.values.map(ModuleName.init)) ?? [])
            return graph.imports(in: scope(paths: setting.paths)).compactMap { importFact -> RuleFailure? in
                guard forbiddenImports.contains(importFact.module) else {
                    return nil
                }

                return violation(
                    severity: setting.severity,
                    path: importFact.file.path,
                    message: "\(importFact.file.component) imports forbidden module \(importFact.module)"
                )
            }
        }
    }

    func evaluateComponentBoundaries(
        graph: ArchitectureGraph,
        rules: ArchitectureRules,
        severity: Severity
    ) -> [RuleFailure] {
        let componentByName = rules.componentByID
        var violations: [RuleFailure] = []

        for edge in graph.componentImportEdges {
            guard let sourceComponent = componentByName[edge.sourceComponent] else {
                continue
            }

            if sourceComponent.forbiddenDependencies.contains(edge.targetComponent) {
                violations.append(
                    violation(
                        severity: severity,
                        path: edge.sourcePath,
                        message: "\(edge.sourceComponent) must not depend on \(edge.importedModule) (\(edge.targetComponent.rawValue))"
                    )
                )
            } else if !sourceComponent.allowedDependencies.contains(edge.targetComponent),
                      edge.targetComponent != edge.sourceComponent {
                violations.append(
                    violation(
                        severity: severity,
                        path: edge.sourcePath,
                        message: "\(edge.sourceComponent) imports undeclared component \(edge.importedModule) (\(edge.targetComponent.rawValue))"
                    )
                )
            }
        }

        return violations
    }

    func evaluateDeclaredDependencyCycles(
        graph architectureGraph: ArchitectureGraph,
        rules: ArchitectureRules,
        severity: Severity
    ) -> [RuleFailure] {
        let graph = Dictionary(
            uniqueKeysWithValues: rules.components.map { component in
                (component.id, component.allowedDependencies)
            }
        )

        for component in rules.components {
            if reaches(component.id, from: component.id, graph: graph, visited: []) {
                let path = firstPath(for: component.id, graph: architectureGraph, rules: rules)
                return [
                    violation(
                        severity: severity,
                        path: path,
                        message: "Declared dependency cycle includes component \(component.id.rawValue)"
                    ),
                ]
            }
        }

        return []
    }

    func evaluateDuplicateOwnership(
        rules: ArchitectureRules,
        severity: Severity
    ) -> [RuleFailure] {
        rules.pathOwnershipConflicts.map { conflict in
            violation(
                severity: severity,
                path: conflict.path.asFilePath ?? fallbackPath,
                message: "\(conflict.owner) path \(conflict.path) overlaps \(conflict.overlappingOwner) path \(conflict.overlappingPath)"
            )
        }
    }

    func reaches(
        _ target: ComponentID,
        from current: ComponentID,
        graph: [ComponentID: Set<ComponentID>],
        visited: Set<ComponentID>
    ) -> Bool {
        let dependencies = graph[current] ?? []
        if dependencies.contains(target) {
            return true
        }

        let nextVisited = visited.union([current])
        for dependency in dependencies where !nextVisited.contains(dependency) {
            if reaches(target, from: dependency, graph: graph, visited: nextVisited) {
                return true
            }
        }

        return false
    }

    func evaluateStoredProperties(
        graph: ArchitectureGraph,
        configuration: StoredPropertyRuleConfiguration
    ) -> [RuleFailure] {
        let excludedPaths = (try? configuration.excludedPaths.map { try RelativePathPrefix($0) }) ?? []

        return graph.storedProperties(in: scope(paths: configuration.paths)).flatMap { propertyFact -> [RuleFailure] in
            guard !excludedPaths.contains(where: { $0.contains(propertyFact.file.path) }) else {
                return []
            }

            return storedPropertyViolations(
                file: propertyFact.file,
                property: propertyFact.property,
                graph: graph,
                configuration: configuration
            )
        }
    }

    func evaluateSyntaxConstructs(
        graph: ArchitectureGraph,
        configuration: SyntaxConstructRuleConfiguration
    ) -> [RuleFailure] {
        let excludedPaths = (try? configuration.excludedPaths.map { try RelativePathPrefix($0) }) ?? []

        return graph.constructs(in: scope(paths: configuration.paths)).compactMap { constructFact -> RuleFailure? in
            guard !excludedPaths.contains(where: { $0.contains(constructFact.file.path) }) else {
                return nil
            }

            guard configuration.disallowedConstructs.contains(constructFact.construct.construct) else {
                return nil
            }

            return violation(
                severity: configuration.severity,
                path: constructFact.file.path,
                message: "Uses imperative construct \(constructFact.construct.construct.rawValue)",
                location: constructFact.construct.location,
                evidence: ViolationEvidence(
                    observed: "imperative construct \(constructFact.construct.construct.rawValue)",
                    expectation: "disallowed constructs: \(configuration.disallowedConstructs.map(\.rawValue).sorted().joined(separator: ", "))"
                )
            )
        }
    }

    func evaluateSyntaxKinds(
        graph: ArchitectureGraph,
        configuration: SyntaxKindRuleConfiguration
    ) -> [RuleFailure] {
        graph.files(in: scope(paths: configuration.paths)).flatMap { file in
            let observedKinds = Set(file.syntaxNodes.nodeKinds.map(SyntaxKindName.init))
            let missingRequiredKinds = configuration.requiredKinds
                .subtracting(observedKinds)
                .map { kind in
                    violation(
                        severity: configuration.severity,
                        path: file.path,
                        message: "Missing required SwiftSyntax node kind \(kind)"
                    )
                }

            let disallowedKinds = configuration.disallowedKinds
                .intersection(observedKinds)
                .map { kind in
                    let node = file.syntaxNodes.nodes.first { SyntaxKindName($0.kind) == kind }
                    let expectedKinds = configuration.disallowedKinds
                        .map(\.rawValue)
                        .sorted()
                        .joined(separator: ", ")
                    return violation(
                        severity: configuration.severity,
                        path: file.path,
                        message: "Uses disallowed SwiftSyntax node kind \(kind)",
                        location: node?.location,
                        evidence: ViolationEvidence(
                            observed: "SwiftSyntax node kind \(kind)",
                            expectation: "disallowed SwiftSyntax node kinds: \(expectedKinds)"
                        )
                    )
                }

            return missingRequiredKinds + disallowedKinds
        }
    }

    func evaluateSyntaxNodes(
        graph: ArchitectureGraph,
        configuration: SyntaxNodeRuleConfiguration
    ) -> [RuleFailure] {
        graph.files(in: scope(paths: configuration.paths)).flatMap { file in
            let missingRequiredNodes = configuration.requiredNodes
                .filter { matcher in
                    !file.syntaxNodes.nodes.contains { matcher.matches($0) }
                }
                .map { matcher in
                    violation(
                        severity: configuration.severity,
                        path: file.path,
                        message: "Missing required SwiftSyntax node \(matcher)"
                    )
            }

            let disallowedNodes = file.syntaxNodes.nodes.compactMap { node -> RuleFailure? in
                guard let matcher = configuration.disallowedNodes.first(where: { $0.matches(node) }) else {
                    return nil
                }

                return violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Uses disallowed SwiftSyntax node \(node.description)",
                    location: node.location,
                    evidence: ViolationEvidence(
                        observed: node.description,
                        expectation: "disallowed SwiftSyntax node matcher: \(matcher)"
                    )
                )
            }

            return missingRequiredNodes + disallowedNodes
        }
    }

    func evaluatePublicDeclarations(
        graph: ArchitectureGraph,
        configuration: PublicDeclarationRuleConfiguration
    ) -> [RuleFailure] {
        let scope = scope(paths: configuration.paths)
        let scopedFiles = graph.files(in: scope)
        let scopedDeclarations = graph.declarations(in: scope)
        let declaredNames = scopedDeclarations.map(\.declaration.name)
        let missingRequiredNames = configuration.requiredNames
            .filter { matcher in
                !declaredNames.contains { matcher.matches($0) }
            }
            .sorted { $0.description < $1.description }
            .map { matcher in
                    violation(
                        severity: configuration.severity,
                        path: scopedFiles.first?.path ?? firstPath(in: scope) ?? fallbackPath,
                        message: "Missing required public declaration \(matcher)"
                    )
                }

        let disallowedNames: [RuleFailure] = scopedDeclarations.compactMap { declarationFact -> RuleFailure? in
            guard configuration.disallowedNames.contains(where: { $0.matches(declarationFact.declaration.name) }) else {
                return nil
            }

            return violation(
                severity: configuration.severity,
                path: declarationFact.file.path,
                message: "Public declaration \(declarationFact.declaration.name.rawValue) is disallowed",
                location: declarationFact.declaration.location,
                evidence: ViolationEvidence(
                    observed: "public declaration \(declarationFact.declaration.name.rawValue)",
                    expectation: "disallowed public declaration matchers: \(configuration.disallowedNames.map(\.description).sorted().joined(separator: ", "))"
                )
            )
        }

        return missingRequiredNames + disallowedNames
    }

    func storedPropertyViolations(
        file: SourceFileFacts,
        property: StoredProperty,
        graph: ArchitectureGraph,
        configuration: StoredPropertyRuleConfiguration
    ) -> [RuleFailure] {
        var violations: [RuleFailure] = []
        let typeName = property.type?.rawValue ?? ""

        if configuration.disallowances.contains(.storedProperty) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) is stored",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue)",
                        expectation: "stored properties are disallowed"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.storedVar), property.isMutable {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) is mutable",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "mutable stored property \(property.name.rawValue)",
                        expectation: "stored vars are disallowed"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.any), StringMatcher.exact("Any").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses Any",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "Any is disallowed in stored property types"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.broadExistential), StringMatcher.prefix("any ").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses a broad existential",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "broad existentials are disallowed in stored property types"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.boolState), StringMatcher.exact("Bool").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses Bool state",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "Bool stored state is disallowed"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.optionalState), isOptionalTypeName(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses optional state",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "Optional stored state is disallowed"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.rawStringIdentity),
           StringMatcher.exact("String").matches(typeName),
           isIdentifiableID(property, graph: graph) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses raw String",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "Identifiable id properties must not use raw String"
                    )
                )
            )
        }

        return violations
    }

    func isOptionalTypeName(_ typeName: String) -> Bool {
        StringMatcher.suffix("?").matches(typeName) || StringMatcher.prefix("Optional<").matches(typeName)
    }

    func isIdentifiableID(_ property: StoredProperty, graph: ArchitectureGraph) -> Bool {
        guard StringMatcher.exact("id").matches(property.name.rawValue),
              let owner = property.owner else {
            return false
        }

        return graph.sourceFiles.contains { file in
            file.nominalTypes.contains { type in
                type.name == owner && type.inheritedTypes.contains(where: isIdentifiable)
            } || file.extensionDeclarations.contains { declaration in
                declaration.extendedType == owner && declaration.inheritedTypes.contains(where: isIdentifiable)
            }
        }
    }

    func isIdentifiable(_ type: TypeName) -> Bool {
        StringMatcher.exact("Identifiable").matches(type.rawValue)
            || StringMatcher.suffix(".Identifiable").matches(type.rawValue)
    }

    func evaluateEnumStateMachines(
        graph: ArchitectureGraph,
        configuration: PathRuleConfiguration
    ) -> [RuleFailure] {
        graph.sourceFiles.compactMap { file in
            guard matchesAny(configuration.paths, file.path) else {
                return nil
            }

            guard !file.enums.contains(where: { StringMatcher.suffix("State").matches($0) }) else {
                return nil
            }

            return violation(
                severity: configuration.severity,
                path: file.path,
                message: "Parser file does not declare an enum state machine"
            )
        }
    }

    func matchesAny(_ patterns: [String], _ path: RelativeFilePath) -> Bool {
        patterns.contains { pattern in
            matches(pattern: pattern, path: path.rawValue)
        }
    }

    func matches(pattern: String, path: String) -> Bool {
        if StringMatcher.contains("**/*").matches(pattern) {
            let parts = pattern.components(separatedBy: "**/*")
            let prefix = parts.first ?? ""
            let suffix = parts.dropFirst().joined(separator: "**/*")
            let prefixMatches = prefix.isEmpty || StringMatcher.prefix(prefix).matches(path)
            let suffixMatches = suffix.isEmpty || StringMatcher.suffix(suffix).matches(path)
            return prefixMatches && suffixMatches
        }

        if StringMatcher.suffix("*").matches(pattern) {
            let prefix = String(pattern.dropLast())
            return prefix.isEmpty || StringMatcher.prefix(prefix).matches(path)
        }

        return StringMatcher.exact(pattern).matches(path) || StringMatcher.prefix(pattern + "/").matches(path)
    }

    func firstPath(
        for component: ComponentID,
        graph: ArchitectureGraph,
        rules: ArchitectureRules
    ) -> RelativeFilePath {
        if let file = graph.sourceFiles.first(where: { $0.component == component }) {
            return file.path
        }

        if let prefix = rules.componentByID[component]?.paths.sorted(by: { $0.rawValue < $1.rawValue }).first,
           let path = try? RelativeFilePath(prefix.rawValue) {
            return path
        }

        return fallbackPath
    }

    func scope(paths: [String]) -> GraphScope {
        GraphScope(paths: (try? paths.map { try RelativePathPrefix($0) }) ?? [])
    }

    func firstPath(in scope: GraphScope) -> RelativeFilePath? {
        switch scope {
        case .all:
            nil
        case .paths(let paths):
            paths.sorted(by: { $0.rawValue < $1.rawValue }).first?.asFilePath
        }
    }

    private var fallbackPath: RelativeFilePath {
        "Package.swift"
    }

    func violation(
        severity: Severity,
        path: RelativeFilePath,
        message: String,
        location: SourcePosition? = nil,
        evidence: ViolationEvidence? = nil
    ) -> RuleFailure {
        RuleFailure(
            path: path,
            location: location,
            message: message,
            evidence: evidence,
            severity: severity
        )
    }
}
