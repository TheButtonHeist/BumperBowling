import SwiftLintFramework

public struct ViolationMatcher: Sendable {
    private let id: String
    private let path: String
    private let line: Int
    private let column: Int
    private let severity: ViolationSeverity
    private let reason: String

    public init(id: String, path: String, line: Int, column: Int, severity: ViolationSeverity = .error, reason: String) {
        self.id = id
        self.path = path
        self.line = line
        self.column = column
        self.severity = severity
        self.reason = reason
    }

    public func matches(_ violation: StyleViolation) -> Bool {
        violation.ruleIdentifier == id && violation.location.file == path
            && violation.location.line == line && violation.location.character == column
            && violation.severity == severity && violation.reason == reason
    }
}
