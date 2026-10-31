import Foundation
import SwiftLintFramework
import SwiftSyntax

/// Repository-relative identity over SwiftLint's cached syntax. Never parses source.
public struct SourceFileContext: Sendable {
    public let file: SwiftLintFile
    public let path: String
    public let syntax: SourceFileSyntax
    public let source: String
    public let locationConverter: SourceLocationConverter

    public init(file: SwiftLintFile, root: URL) {
        self.file = file
        self.source = file.contents
        let syntax = file.syntaxTree
        self.syntax = syntax
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let absolute = file.path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path } ?? ""
        let path = absolute.hasPrefix(prefix) ? String(absolute.dropFirst(prefix.count)) : absolute
        self.path = path
        self.locationConverter = file.locationConverter
    }

    public func failure(at node: some SyntaxProtocol, message: String) -> RuleFailure {
        let position = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        return RuleFailure(location: Location(file: file.path, line: position.line, character: position.column), message: message)
    }
}

public struct RuleFailure: Sendable {
    public let location: Location
    public let message: String

    public init(location: Location, message: String) {
        self.location = location
        self.message = message
    }
}
