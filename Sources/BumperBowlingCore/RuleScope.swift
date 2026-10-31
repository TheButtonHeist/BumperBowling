/// File selection uses repository-relative paths, independent of collection.
public struct RuleScope: Sendable {
    private let paths: [String]
    private let predicate: @Sendable (SourceFileContext) -> Bool

    public init(_ predicate: @escaping @Sendable (SourceFileContext) -> Bool) {
        self.init(paths: [], predicate: predicate)
    }

    private init(paths: [String], predicate: @escaping @Sendable (SourceFileContext) -> Bool) {
        self.paths = paths
        self.predicate = predicate
    }

    public static let repository = RuleScope { _ in true }
    public static func under(_ path: String) -> Self {
        Self(paths: [path]) { $0.path == path || $0.path.hasPrefix(path + "/") }
    }
    public static func files(_ paths: Set<String>) -> Self {
        Self(paths: paths.sorted()) { paths.contains($0.path) }
    }
    public func excluding(_ other: Self) -> Self {
        Self(paths: paths + other.paths) { self.includes($0) && !other.includes($0) }
    }
    public func includes(_ file: SourceFileContext) -> Bool { predicate(file) }

    static func union(_ scopes: [Self]) -> Self {
        Self(paths: scopes.flatMap(\.paths)) { file in scopes.contains { $0.includes(file) } }
    }

    func validate() throws {
        for path in paths { try RepositoryScanner.validateRelativePath(path) }
    }
}
