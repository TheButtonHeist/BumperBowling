import Foundation

public struct ArchitectureRules: Equatable, Sendable {
    let configuration: ArchitectureConfiguration
    public let includedPaths: Set<RelativePathPrefix>
    public let excludedPaths: Set<RelativePathPrefix>
    public let components: [ComponentRule]
    public let componentByID: [ComponentID: ComponentRule]
    public let componentByModule: [ModuleName: ComponentID]
    public let pathOwnershipConflicts: [PathOwnershipConflict]
    public let forbiddenImports: Set<ModuleName>
    public let ruleConfiguration: RuleConfiguration

    public init(configuration: ArchitectureConfiguration) throws {
        self.configuration = configuration
        self.includedPaths = Set(try configuration.includedPaths.map { try RelativePathPrefix($0) })
        self.excludedPaths = Set(try configuration.excludedPaths.map { try RelativePathPrefix($0) })
        try Self.validateRuleConfiguration(configuration.rules)

        var components: [ComponentRule] = []
        var componentByID: [ComponentID: ComponentRule] = [:]
        var componentByModule: [ModuleName: ComponentID] = [:]
        var ownedPaths: [PathOwnership] = []
        var pathOwnershipConflicts: [PathOwnershipConflict] = []

        for componentConfiguration in configuration.components {
            let component = try ComponentRule(configuration: componentConfiguration)

            guard componentByID[component.id] == nil else {
                throw ConfigurationError.duplicateComponent(component.id.rawValue)
            }

            for module in component.modules {
                guard componentByModule[module] == nil else {
                    throw ConfigurationError.duplicateModule(module.rawValue)
                }
                componentByModule[module] = component.id
            }

            for path in component.paths.sorted(by: { $0.rawValue < $1.rawValue }) {
                if let overlappingOwnership = ownedPaths.first(where: { $0.path.overlaps(path) }) {
                    pathOwnershipConflicts.append(
                        PathOwnershipConflict(
                            path: path,
                            owner: component.id,
                            overlappingPath: overlappingOwnership.path,
                            overlappingOwner: overlappingOwnership.owner
                        )
                    )
                }
                ownedPaths.append(PathOwnership(path: path, owner: component.id))
            }

            components.append(component)
            componentByID[component.id] = component
        }

        let ids = Set(components.map(\.id))
        for component in components {
            for dependency in component.allowedDependencies.union(component.forbiddenDependencies) where !ids.contains(dependency) {
                throw ConfigurationError.unknownDependency(component.id.rawValue, dependency.rawValue)
            }
        }

        self.components = components
        self.componentByID = componentByID
        self.componentByModule = componentByModule
        self.pathOwnershipConflicts = pathOwnershipConflicts
        self.forbiddenImports = Set(try configuration.rules.forbiddenImports.flatMap(\.values).map(ModuleName.init))
        self.ruleConfiguration = configuration.rules
    }

    private static func validateRuleConfiguration(_ configuration: RuleConfiguration) throws {
        for setting in configuration.forbiddenImports {
            _ = try setting.values.map(ModuleName.init)
            _ = try setting.paths.map { try RelativePathPrefix($0) }
        }

        for setting in configuration.storedPropertyRules {
            _ = try setting.paths.map { try RelativePathPrefix($0) }
            _ = try setting.excludedPaths.map { try RelativePathPrefix($0) }
        }
        for setting in configuration.syntaxConstructRules {
            _ = try setting.paths.map { try RelativePathPrefix($0) }
            _ = try setting.excludedPaths.map { try RelativePathPrefix($0) }
        }
        for setting in configuration.syntaxKindRules {
            _ = try setting.paths.map { try RelativePathPrefix($0) }
        }
        for setting in configuration.syntaxNodeRules {
            _ = try setting.paths.map { try RelativePathPrefix($0) }
        }
        for setting in configuration.publicDeclarationRules {
            _ = try setting.paths.map { try RelativePathPrefix($0) }
        }
        for setting in configuration.enumStateMachineRules {
            _ = try setting.paths.map { try RelativePathPrefix($0) }
        }
    }

    public func component(containing relativePath: RelativeFilePath) -> ComponentRule? {
        components.first { component in
            component.paths.contains { $0.contains(relativePath) }
        }
    }

    public func includes(_ relativePath: RelativeFilePath) -> Bool {
        let included = includedPaths.isEmpty || includedPaths.contains { $0.contains(relativePath) }
        let excluded = excludedPaths.contains { $0.contains(relativePath) }
        return included && !excluded
    }
}

public struct ComponentRule: Equatable, Sendable {
    public let id: ComponentID
    public let modules: Set<ModuleName>
    public let paths: Set<RelativePathPrefix>
    public let allowedDependencies: Set<ComponentID>
    public let forbiddenDependencies: Set<ComponentID>

    init(configuration: ComponentConfiguration) throws {
        let id = try ComponentID(configuration.name)
        let configuredModules = try configuration.modules.map(ModuleName.init)
        let modules = Set(configuredModules + [try ModuleName(configuration.name)])

        self.id = id
        self.modules = modules
        self.paths = Set(try configuration.paths.map { try RelativePathPrefix($0) })
        self.allowedDependencies = Set(try configuration.mayDependOn.map(ComponentID.init))
        self.forbiddenDependencies = Set(try configuration.mustNotDependOn.map(ComponentID.init))

        guard !paths.isEmpty else {
            throw ConfigurationError.emptyComponentPaths(id.rawValue)
        }
    }
}

public struct PathOwnershipConflict: Equatable, Sendable {
    public let path: RelativePathPrefix
    public let owner: ComponentID
    public let overlappingPath: RelativePathPrefix
    public let overlappingOwner: ComponentID
}

private struct PathOwnership {
    let path: RelativePathPrefix
    let owner: ComponentID
}

public struct ComponentID: Hashable, Sendable, CustomStringConvertible, Codable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyComponentName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ModuleName: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConfigurationError.emptyModuleName
        }
        self.rawValue = normalized
    }

    public var description: String {
        rawValue
    }
}

public struct RelativeFilePath: Hashable, Sendable, CustomStringConvertible, Codable {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        self.rawValue = try normalizedRelativePath(rawValue)
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RelativePathPrefix: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        self.rawValue = try normalizedRelativePath(rawValue)
    }

    public func contains(_ relativePath: RelativeFilePath) -> Bool {
        StringMatcher.exact(rawValue).matches(relativePath) || StringMatcher.prefix(rawValue + "/").matches(relativePath)
    }

    public func overlaps(_ other: RelativePathPrefix) -> Bool {
        StringMatcher.exact(rawValue).matches(other)
            || StringMatcher.prefix(other.rawValue + "/").matches(rawValue)
            || StringMatcher.prefix(rawValue + "/").matches(other)
    }

    public var description: String {
        rawValue
    }
}

public enum ConfigurationError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptyComponentName
    case emptyModuleName
    case emptySyntaxKindName
    case emptyPath
    case emptyDeclarationName
    case emptyAttributeName
    case emptyTypeName
    case emptyComponentPaths(String)
    case duplicateComponent(String)
    case duplicateModule(String)
    case duplicatePath(String)
    case unsafePath(String)
    case unknownDependency(String, String)

    public var description: String {
        switch self {
        case .emptyComponentName:
            "Component names cannot be empty."
        case .emptyModuleName:
            "Module names cannot be empty."
        case .emptySyntaxKindName:
            "SwiftSyntax node kind names cannot be empty."
        case .emptyPath:
            "Component paths cannot be empty."
        case .emptyDeclarationName:
            "Declaration names cannot be empty."
        case .emptyAttributeName:
            "Attribute names cannot be empty."
        case .emptyTypeName:
            "Type names cannot be empty."
        case .emptyComponentPaths(let component):
            "Component \(component) must own at least one path."
        case .duplicateComponent(let component):
            "Duplicate component: \(component)."
        case .duplicateModule(let module):
            "Duplicate module alias: \(module)."
        case .duplicatePath(let path):
            "Duplicate component path: \(path)."
        case .unsafePath(let path):
            "Paths must be relative and stay within the repository: \(path)."
        case .unknownDependency(let component, let dependency):
            "Component \(component) references unknown dependency \(dependency)."
        }
    }
}

private func normalizedRelativePath(_ rawValue: String) throws -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw ConfigurationError.emptyPath
    }

    guard !StringMatcher.prefix("/").matches(trimmed) else {
        throw ConfigurationError.unsafePath(rawValue)
    }

    let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.isEmpty,
          !components.contains(where: { component in
              let component = String(component)
              return component.isEmpty
                  || StringMatcher.exact(".").matches(component)
                  || StringMatcher.exact("..").matches(component)
          }) else {
        throw ConfigurationError.unsafePath(rawValue)
    }

    return normalized
}
