import BumperBowlingCore
import Foundation
import SwiftLintFramework
import Testing

@Test func collectedSyntaxAndLocationsSurviveSwiftLintCacheEviction() throws {
    let source = "struct Original {\n    let name = 1\n}"
    let native = SwiftLintFile(contents: source)
    let context = SourceFileContext(file: native, root: FileManager.default.temporaryDirectory)
    let property = try #require(variables().storedMembers().matches(in: context).first)
    // SwiftLint evicts each validated file's caches before validating later files.
    native.file.contents = "struct Changed {}"
    native.invalidateCache()
    #expect(context.source == source)
    #expect(structs().matches(in: context).map(\.name) == ["Original"])
    let finding = property.failure(message: "Original property")
    #expect(finding.location.line == 2)
    #expect(finding.location.character == 5)
}
