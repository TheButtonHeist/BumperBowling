import Foundation
import SwiftLintFramework

/// Runs native SwiftLint rules. Tests and the repository executable use this same path.
public enum BumperRunner {
    public static func evaluate(
        _ rules: [any Rule.Type],
        files: [SwiftLintFile],
        root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> [StyleViolation] {
        guard !rules.isEmpty else { throw BumperError("Register at least one rule.") }
        let sources = files.map { SourceFileContext(file: $0, root: root) }
        let contexts = Dictionary(sources.compactMap { context in
            context.file.path.map { ($0, context) }
        }, uniquingKeysWith: { first, _ in first })
        var identifiers: Set<String> = []
        var settings: [String: Any] = [:]
        var definitions: [String: any NativeBumperRule] = [:]
        for rule in rules {
            guard identifiers.insert(rule.identifier).inserted else {
                throw BumperError("Duplicate rule identifier: \(rule.identifier)")
            }
            if let type = rule as? any NativeBumperRule.Type {
                let values = ["repository_root": root.standardizedFileURL.path]
                let definition = try type.init(configuration: values)
                definitions[rule.identifier] = definition
                try definition.checkInput(sources)
                settings[rule.identifier] = values
            }
            guard rule.init() is any SourceKitFreeRule else {
                throw BumperError("\(rule.identifier) must conform to SourceKitFreeRule. Bumper runs syntax checks.")
            }
        }
        let configuration = try Configuration(
            dict: settings, ruleList: RuleList(rules: rules), enableAllRules: true
        )
        let storage = RuleStorage()
        // Collect every file before validating any cross-file rule.
        let collected = files.map {
            Linter(file: $0, configuration: configuration, cache: nil).collect(into: storage)
        }
        let violations = collected.flatMap { $0.styleViolations(using: storage) }
        for violation in violations {
            if let definition = definitions[violation.ruleIdentifier] {
                guard let path = violation.location.file, let context = contexts[path], definition.scope.includes(context) else {
                    throw BumperError("\(violation.ruleIdentifier) reported a diagnostic outside its subject scope.")
                }
            }
        }
        return violations.sorted {
            if $0.location != $1.location { return $0.location < $1.location }
            if $0.ruleIdentifier != $1.ruleIdentifier { return $0.ruleIdentifier < $1.ruleIdentifier }
            return $0.reason < $1.reason
        }
    }

    public static func lint(
        _ rules: [any Rule.Type],
        root: URL,
        included: [String] = ["Sources"],
        excluded: [String] = []
    ) throws -> [StyleViolation] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let files = try RepositoryScanner(included: included, excluded: excluded).scan(root: root)
        return try evaluate(rules, files: files, root: root).map { violation in
            let prefix = root.standardizedFileURL.path + "/"
            guard let path = violation.location.file, path.hasPrefix(prefix) else { return violation }
            return violation.with(location: Location(
                file: String(path.dropFirst(prefix.count)),
                line: violation.location.line,
                character: violation.location.character
            ))
        }
    }

    /// Entry point for the repository's ordinary Swift executable.
    /// `bumper lint` isolates this executable; direct SwiftPM runs use normal access.
    public static func main(
        rules: [any Rule.Type],
        included: [String] = ["Sources"],
        excluded: [String] = []
    ) {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count <= 1, !arguments.contains(where: { $0.hasPrefix("-") }) else {
                throw BumperError("Usage: BumperRulesRunner [repository-root]")
            }
            let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
            let violations = try lint(rules, root: root, included: included, excluded: excluded)
            let output = reporterFrom(identifier: "xcode").generateReport(violations)
            if !output.isEmpty { print(output) }
            Foundation.exit(violations.contains(where: { $0.severity == .error }) ? 1 : 0)
        } catch {
            FileHandle.standardError.write(Data("bumper: \(error)\n".utf8))
            Foundation.exit(2)
        }
    }
}
