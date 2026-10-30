import Foundation

public enum BumperCommands {
    public static func initialize(at root: URL) throws {
        try ConfigurationLoader.writeSample(to: root)
        print("Created sample \(ConfigurationLoader.fileName)")
        print("Run `bumper lint \(root.path)` to validate this repository.")
    }

    public static func scan(root: URL) async throws -> String {
        try await scan(root: root, configuration: ConfigurationLoader.loadConfiguration(root: root))
    }

    public static func scan(root: URL, configuration: ArchitectureConfiguration) async throws -> String {
        try await scanReport(root: root, configuration: configuration).markdownSummary
    }

    public static func scanReport(
        root: URL,
        progress: BumperProgressReporter = .disabled
    ) async throws -> ScanReport {
        progress.report("Loading configuration")
        return try await scanReport(
            root: root,
            configuration: ConfigurationLoader.loadConfiguration(root: root),
            progress: progress
        )
    }

    public static func scanReport(
        root: URL,
        configuration: ArchitectureConfiguration,
        progress: BumperProgressReporter = .disabled
    ) async throws -> ScanReport {
        progress.report("Preparing architecture rules")
        let scanner = try RepositoryScanner(configuration: configuration)
        progress.report("Scanning Swift source files")
        let model = try await scanner.scan(root: root)
        progress.report("Parsed \(model.files.count) Swift source file(s)")
        return ScanReport(repository: model)
    }

    public static func snapshot(root: URL) throws -> String {
        try snapshot(configuration: ConfigurationLoader.loadConfiguration(root: root))
    }

    public static func snapshot(configuration: ArchitectureConfiguration) throws -> String {
        return try ArchitectureSnapshot(configuration: configuration).render()
    }

    public static func lint(root: URL) async throws -> RuleReport {
        try await lintRun(root: root).report
    }

    public static func lint(root: URL, configuration: ArchitectureConfiguration) async throws -> RuleReport {
        try await lintRun(root: root, configuration: configuration).report
    }

    /// Runs the repository-owned rule tests under `.bumper/Tests` and returns
    /// the underlying SwiftPM exit status.
    public static func test(root: URL) throws -> Int32 {
        try ConfigurationLoader.runConsumerTests(root: root)
    }

    public static func lintRun(
        root: URL,
        progress: BumperProgressReporter = .disabled
    ) async throws -> LintRunResult {
        progress.report("Loading configuration")
        return try await lintRun(
            root: root,
            configuration: ConfigurationLoader.loadConfiguration(root: root),
            progress: progress
        )
    }

    public static func lintRun(
        root: URL,
        configuration: ArchitectureConfiguration,
        progress: BumperProgressReporter = .disabled
    ) async throws -> LintRunResult {
        try await LintRunEngine(
            root: root,
            configuration: configuration,
            progress: progress
        ).run()
    }

    public static func checkConfiguration(root: URL) throws -> ConfigurationReport {
        do {
            let configuration = try ConfigurationLoader.loadConfiguration(root: root)
            _ = try ArchitectureRules(configuration: configuration)
            return ConfigurationReport(problem: nil)
        } catch {
            return ConfigurationReport(problem: String(describing: error))
        }
    }

    public static func explain(path: URL, root: URL) async throws -> String {
        try await explain(
            path: path,
            root: root,
            configuration: ConfigurationLoader.loadConfiguration(root: root)
        )
    }

    public static func explain(path: URL, root: URL, configuration: ArchitectureConfiguration) async throws -> String {
        let scanner = try RepositoryScanner(configuration: configuration)
        let file = try await scanner.scanFile(path, root: root)

        var lines: [String] = []
        lines.append("# \(file.path.rawValue)")
        lines.append("")
        lines.append("Component: \(file.component?.rawValue ?? "none")")
        let imports = file.imports.map(\.rawValue).joined(separator: ", ")
        lines.append("Imports: \(imports.isEmpty ? "none" : imports)")
        lines.append("")
        lines.append("## Public API")

        if file.publicDeclarations.isEmpty {
            lines.append("None detected.")
        } else {
            for declaration in file.publicDeclarations {
                lines.append("- \(declaration.kind.rawValue) \(declaration.name.rawValue)")
            }
        }

        return lines.joined(separator: "\n")
    }

}

public struct ConfigurationReport: Equatable, Sendable {
    public let problem: String?

    public var isValid: Bool {
        problem == nil
    }

    public var summary: String {
        if let problem {
            return "The configuration is not valid: \(problem)"
        }
        return "The configuration is valid."
    }
}
