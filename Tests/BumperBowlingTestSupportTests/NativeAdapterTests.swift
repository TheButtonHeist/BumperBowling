import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftLintFramework
import SwiftSyntax
import Testing

@Test func genericAdaptersKeepNativeIdentityAndTypedCollectionSeparate() throws {
    let harness = RuleTestHarness {
        FirstSyntaxAuthor.self
        SecondSyntaxAuthor.self
        PathAuthor.self
        CountAuthor.self
        FixtureRule.self
    }
    let passing = try harness.evaluate([
        .swift("Sources/Subject.swift", source: "// swiftlint:disable adapter.first adapter.second fixture_rule\nstruct Subject {}"),
        .swift("Sources/Evidence.swift", source: "// swiftlint:disable fixture_rule\nwitness()"),
    ])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([
        .swift("Sources/Subject.swift", source: "struct Subject {}"),
        .swift("Sources/Evidence.swift", source: "// swiftlint:disable fixture_rule\nunrelated()"),
    ])
    #expect(failing.count == 5)
    #expect(failing.filter(ViolationMatcher(
        id: "fixture_rule", path: "Sources/Subject.swift", line: 1, column: 1, reason: "Fixture finding"
    ).matches).count == 1)
    for identifier in ["adapter.first", "adapter.second", "adapter.paths", "adapter.count"] {
        #expect(failing.filter(ViolationMatcher(
            id: identifier, path: "Sources/Subject.swift", line: 1, column: 1, reason: identifier
        ).matches).count == 1)
    }
}

private enum FirstSyntaxAuthor: SyntaxRule {
    static let metadata = RuleMetadata(id: "adapter.first", summary: "First adapter")
    static var body: SyntaxCheck {
        Rules.forbid(structs(), scope: .files(["Sources/Subject.swift"])) { _ in metadata.id }
    }
}

private enum SecondSyntaxAuthor: SyntaxRule {
    static let metadata = RuleMetadata(id: "adapter.second", summary: "Second adapter")
    static var body: SyntaxCheck {
        Rules.forbid(structs(), scope: .files(["Sources/Subject.swift"])) { _ in metadata.id }
    }
}

private enum PathAuthor: RepositoryRule {
    typealias FileInfo = String
    static let metadata = RuleMetadata(id: "adapter.paths", summary: "Relative paths survive root configuration")
    static var body: RepositoryCheck<FileInfo> {
        Rules.repository(scope: .files(["Sources/Subject.swift"]), collect: { file in
            functionCalls().named("witness").matches(in: file).isEmpty ? "" : file.path
        }, check: { file, inventory in
            Rules.files { _ in
                inventory.contains("Sources/Evidence.swift") ? [] : [file.failure(at: file.syntax, message: metadata.id)]
            }
        })
    }
}

private enum CountAuthor: RepositoryRule {
    typealias FileInfo = Int
    static let metadata = RuleMetadata(id: "adapter.count", summary: "Independent numeric collection")
    static var body: RepositoryCheck<FileInfo> {
        Rules.repository(scope: .files(["Sources/Subject.swift"]), collect: { file in
            functionCalls().named("witness").matches(in: file).count
        }, check: { file, inventory in
            Rules.files { _ in
                inventory.reduce(0, +) == 1 ? [] : [file.failure(at: file.syntax, message: metadata.id)]
            }
        })
    }
}
