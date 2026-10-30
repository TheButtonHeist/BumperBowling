import Foundation
import SwiftParser
import SwiftSyntax

/// One parsed source file: typed descriptor, source text, syntax, location
/// conversion, and failure construction.
public struct SourceFileContext: Sendable {
    public let descriptor: SourceFileDescriptor
    public let source: String
    public let syntax: SourceFileSyntax
    public let locationConverter: SourceLocationConverter

    /// Parses the source exactly once.
    public init(descriptor: SourceFileDescriptor, source: String) {
        let syntax = Parser.parse(source: source)
        self.descriptor = descriptor
        self.source = source
        self.syntax = syntax
        self.locationConverter = SourceLocationConverter(fileName: descriptor.path.rawValue, tree: syntax)
    }

    /// Missing source text is an explicit failure, not a skipped file.
    init(file: SourceFileFacts) throws {
        guard let source = file.source else {
            throw RuleEvaluationError.missingSource(file.path)
        }
        self.init(
            descriptor: SourceFileDescriptor(path: file.path, component: file.component),
            source: source
        )
    }

    public var path: RelativeFilePath {
        descriptor.path
    }

    public var component: ComponentID? {
        descriptor.component
    }

    public func position(of node: some SyntaxProtocol) -> SourcePosition {
        let sourceLocation = locationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SourcePosition(line: sourceLocation.line, column: sourceLocation.column)
    }

    public func failure(
        at node: some SyntaxProtocol,
        message: String,
        evidence: ViolationEvidence? = nil
    ) -> RuleFailure {
        RuleFailure(
            path: path,
            location: position(of: node),
            message: message,
            evidence: evidence
        )
    }
}
