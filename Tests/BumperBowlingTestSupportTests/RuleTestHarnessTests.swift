import BumperBowlingCore
import BumperBowlingTestSupport
import Foundation
import SwiftLintFramework
import Testing

@Suite("Native rule fixtures")
struct RuleTestHarnessTests {
    @Test func preservesPathsAndUsesSwiftLintDisableCommands() throws {
        let harness = RuleTestHarness(FixtureRule.self)
        let path = "Sources/Spaced folder/Cafe\u{301}.swift"
        let passing = try harness.evaluate([.swift(path, source: "// swiftlint:disable fixture_rule\nstruct Example {}")])
        #expect(passing.isEmpty)
        let failing = try harness.evaluate([.swift(path, source: "struct Example {}")])
        #expect(failing.count == 1)
        #expect(failing.filter(ViolationMatcher(id: "fixture_rule", path: path, line: 1, column: 1, reason: "Fixture finding").matches).count == 1)
    }

    @Test(arguments: ["../Escape.swift", "/Outside.swift", "Sources//Empty.swift", "Sources/./Dot.swift", "Sources/NotSwift.txt"])
    func rejectsUnsafeFixturePaths(path: String) {
        #expect(throws: BumperError.self) { try RuleTestHarness(FixtureRule.self).evaluate([.swift(path, source: "")]) }
    }

    @Test func rejectsFindingsAnchoredOutsideTheSelectedSubjects() throws {
        do {
            _ = try RuleTestHarness(MisplacedFindingRule.self).evaluate([
                .swift("Sources/Subject.swift", source: "struct Subject {}"),
                .swift("Sources/Other.swift", source: "struct Other {}"),
            ])
            Issue.record("Expected the subject-scope check to reject this finding.")
        } catch let error as BumperError {
            #expect(error.description.contains("outside its subject scope"))
        }
    }

    @Test func rejectsInvalidScopePathsBeforeTheyBecomeAnEmptySelection() {
        #expect(throws: BumperError.self) {
            try RuleTestHarness(InvalidScopeRule.self).evaluate([.swift("Sources/File.swift", source: "struct File {}")])
        }
    }

    @Test func rejectsDuplicateFixturePaths() {
        #expect(throws: BumperError.self) {
            try RuleTestHarness(FixtureRule.self).evaluate([.swift("Same.swift", source: "one"), .swift("Same.swift", source: "two")])
        }
    }

    @Test func rejectsDuplicateRuleIDsInsteadOfSilentlyOverwriting() {
        #expect(throws: BumperError.self) {
            try RuleTestHarness([FixtureRule.self, FixtureRule.self]).evaluate([.swift("File.swift", source: "struct Example {}")])
        }
    }
}

private struct FixtureRule: SourceKitFreeRule {
    var configuration = SeverityConfiguration<Self>(.error)
    static let description = RuleDescription(identifier: "fixture_rule", name: "Fixture Rule", description: "Fixture finding", kind: .lint)
    func validate(file: SwiftLintFile) -> [StyleViolation] {
        [StyleViolation(ruleDescription: Self.description, severity: configuration.severity,
                        location: Location(file: file, position: file.syntaxTree.positionAfterSkippingLeadingTrivia), reason: "Fixture finding")]
    }
}

private struct MisplacedFindingRule: SyntaxRule {
    var configuration = RuleSettings<Self>()
    static let metadata = RuleMetadata(id: "misplaced_finding", summary: "Subject scope contract")
    var body: SyntaxCheck {
        Rules.files(scope: .files(["Sources/Subject.swift"])) { file in
            let path = file.file.path?.replacingOccurrences(of: "Subject.swift", with: "Other.swift")
            return [RuleFailure(location: Location(file: path, line: 1, character: 1), message: "Wrong subject")]
        }
    }
}

private struct InvalidScopeRule: SyntaxRule {
    var configuration = RuleSettings<Self>()
    static let metadata = RuleMetadata(id: "invalid_scope", summary: "Invalid scope contract")
    var body: SyntaxCheck { Rules.files(scope: .under("../Sources")) { _ in [] } }
}
