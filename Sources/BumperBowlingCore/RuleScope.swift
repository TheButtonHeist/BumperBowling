/// File selection uses repository-relative paths, independent of collection.
public struct RuleScope: Sendable, CustomStringConvertible {
    private let paths: [String]
    public let description: String
    private let predicate: @Sendable (SourceFileContext) -> Bool

    public init(_ predicate: @escaping @Sendable (SourceFileContext) -> Bool) {
        self.init(paths: [], description: "a custom scope", predicate: predicate)
    }

    private init(paths: [String], description: String, predicate: @escaping @Sendable (SourceFileContext) -> Bool) {
        self.paths = paths
        self.description = description
        self.predicate = predicate
    }

    public static let repository = RuleScope(paths: [], description: "the repository") { _ in true }
    public static func under(_ path: String) -> Self {
        Self(paths: [path], description: "at or under \(String(reflecting: path))") { $0.path == path || $0.path.hasPrefix(path + "/") }
    }
    public static func files(_ paths: Set<String>) -> Self {
        Self(paths: paths.sorted(), description: paths.isEmpty ? "no files" : paths.sorted().map { String(reflecting: $0) }.joined(separator: ", ")) { paths.contains($0.path) }
    }
    public func union(_ other: Self) -> Self {
        Self.union([self, other])
    }

    public func excluding(_ other: Self) -> Self {
        Self(paths: paths + other.paths, description: "(\(description)) except (\(other.description))") { self.includes($0) && !other.includes($0) }
    }
    public func includes(_ file: SourceFileContext) -> Bool { predicate(file) }

    static func union(_ scopes: [Self]) -> Self {
        Self(paths: scopes.flatMap(\.paths), description: scopes.map { "(\($0.description))" }.joined(separator: " or ")) { file in scopes.contains { $0.includes(file) } }
    }

    // Validate referenced scopes without changing which files are subjects.
    func validating(_ scopes: [Self]) -> Self {
        Self(paths: paths + scopes.flatMap(\.paths), description: description, predicate: predicate)
    }

    func validate() throws {
        for path in paths { try RepositoryScanner.validateRelativePath(path) }
    }
}
