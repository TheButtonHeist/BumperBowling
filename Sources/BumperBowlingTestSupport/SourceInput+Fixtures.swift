import BumperBowlingCore

public extension SourceInput {
    /// Invalid fixture paths or components fail at construction.
    static func swift(_ path: String, component: String? = nil, source: String) -> Self {
        do {
            return try Self(
                path: RelativeFilePath(path),
                component: component.map(ComponentID.init),
                source: source
            )
        } catch {
            preconditionFailure("Invalid source fixture: \(error)")
        }
    }
}
