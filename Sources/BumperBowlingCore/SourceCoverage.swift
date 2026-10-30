import Foundation

/// Coverage of included, non-excluded source files. Counts describe lexical
/// file extensions, not build targets or compiler-verified language identity.
public struct SourceCoverageSummary: Equatable, Sendable, Codable {
    public let includedFileCount: Int
    public let scannedFileCount: Int
    public let unownedFileCount: Int
    public let unownedPaths: [RelativeFilePath]
    public let overlappingPaths: [RelativeFilePath]
    public let languages: [SourceLanguageCoverage]
    public let scopes: [SourceScopeCoverage]

    static func isSource(_ path: RelativeFilePath) -> Bool {
        ["swift", "m", "mm", "h", "c", "cc", "cpp", "cxx", "hpp"].contains(fileExtension(path))
    }

    private static func fileExtension(_ path: RelativeFilePath) -> String {
        (path.rawValue as NSString).pathExtension
    }

    init(paths: [RelativeFilePath], rules: ArchitectureRules) {
        let paths = paths.sorted { $0.rawValue < $1.rawValue }
        let swiftPaths = paths.filter { StringMatcher.exact("swift").matches(Self.fileExtension($0)) }
        let owners = swiftPaths.map { path in
            rules.components.filter { component in component.paths.contains { $0.contains(path) } }
        }
        let scannedFileCount = owners.filter { !$0.isEmpty }.count
        self.includedFileCount = paths.count
        self.scannedFileCount = scannedFileCount
        self.unownedPaths = zip(swiftPaths, owners).compactMap { $1.isEmpty ? $0 : nil }
        self.unownedFileCount = unownedPaths.count
        self.overlappingPaths = zip(swiftPaths, owners).compactMap { $1.count > 1 ? $0 : nil }
        self.languages = Dictionary(grouping: paths, by: Self.fileExtension).map { language, paths in
            SourceLanguageCoverage(
                fileExtension: language,
                isSupported: StringMatcher.exact("swift").matches(language),
                includedFileCount: paths.count,
                scannedFileCount: StringMatcher.exact("swift").matches(language) ? scannedFileCount : 0
            )
        }.sorted { $0.fileExtension < $1.fileExtension }
        self.scopes = rules.components.flatMap { component in
            component.paths.map { scope in
                let matched = paths.filter { scope.contains($0) }
                return SourceScopeCoverage(
                    component: component.id.rawValue,
                    path: scope.rawValue,
                    supportedFileCount: matched.filter { StringMatcher.exact("swift").matches(Self.fileExtension($0)) }.count,
                    unsupportedFileCount: matched.filter { !StringMatcher.exact("swift").matches(Self.fileExtension($0)) }.count
                )
            }
        }.sorted { ($0.component, $0.path) < ($1.component, $1.path) }
    }

    func failures(severity: Severity) -> [RuleFailure] {
        var failures = unownedPaths.map { path in
            RuleFailure(
                path: path,
                message: "Included Swift source has no component owner. Add a component path covering \(path.rawValue), or exclude it explicitly."
            )
        }
        failures += overlappingPaths.map { path in
            RuleFailure(path: path, message: "Included Swift source has multiple component owners. Narrow the overlapping component paths.")
        }
        failures += scopes.compactMap { scope in
            guard scope.supportedFileCount == 0, let path = try? RelativeFilePath(scope.path) else { return nil }
            return RuleFailure(
                path: path,
                message: scope.unsupportedFileCount == 0
                    ? "Component \(scope.component) path \(scope.path) matches no included source files. Check the path and scan exclusions."
                    : "Component \(scope.component) path \(scope.path) contains only unsupported source languages; SwiftSyntax did not check its contents.",
                severity: scope.unsupportedFileCount == 0 ? (severity == .error ? .warning : severity) : .note
            )
        }
        return failures
    }
}

public struct SourceLanguageCoverage: Equatable, Sendable, Codable {
    public let fileExtension: String
    public let isSupported: Bool
    public let includedFileCount: Int
    public let scannedFileCount: Int
}

public struct SourceScopeCoverage: Equatable, Sendable, Codable {
    public let component: String
    public let path: String
    public let supportedFileCount: Int
    public let unsupportedFileCount: Int
}
