/// One named Swift source fixture. It is never compiled as application code.
public struct SourceInput: Sendable {
    public let path: String
    public let source: String

    public static func swift(_ path: String, source: String) -> Self {
        Self(path: path, source: source)
    }
}
