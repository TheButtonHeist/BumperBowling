import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Test func importOwnershipKeepsScopedAndSelectiveImportsAtTheBoundary() throws {
    let harness = RuleTestHarness(NetworkOwnership.self)
    let passing = try harness.evaluate([
        .swift("Sources/Transport/Socket.swift", source: "import Network"),
        .swift("Sources/TLS.swift", source: "@preconcurrency import Network"),
        .swift("Sources/Domain/Model.swift", source: "import Foundation\nimport NetworkExtras"),
    ])
    #expect(passing.isEmpty)
    let failing = try harness.evaluate([
        .swift("Sources/TransportExtras/Socket.swift", source: "import Network"),
        .swift("Sources/Domain/Model.swift", source: "import struct Network.NWEndpoint"),
    ])
    #expect(failing.count == 2)
    for path in ["Sources/TransportExtras/Socket.swift", "Sources/Domain/Model.swift"] {
        #expect(failing.filter(ViolationMatcher(
            id: "boundary.network", path: path, line: 1, column: 1,
            reason: "Import Network is outside its allowed boundary. Allowed locations: (at or under \"Sources/Transport\") or (\"Sources/TLS.swift\"). Move the code that needs this import to an allowed location."
        ).matches).count == 1)
    }
}

@Test func forbiddenImportsRespectSubjectsAndWholeModuleNames() throws {
    let harness = RuleTestHarness(DomainImports.self)
    #expect(try harness.evaluate([
        .swift("Sources/UI/Screen.swift", source: "import UIKit"),
        .swift("Sources/Domain/Model.swift", source: "import Foundation\nimport UIKitExtras"),
    ]).isEmpty)
    let failing = try harness.evaluate([
        .swift("Sources/Domain/Model.swift", source: "import UIKit\nimport SwiftUI"),
    ])
    #expect(failing.count == 2)
    for (line, module) in [(1, "UIKit"), (2, "SwiftUI")] {
        #expect(failing.filter(ViolationMatcher(
            id: "boundary.domain", path: "Sources/Domain/Model.swift", line: line, column: 1,
            reason: "Import \(module) is forbidden in this scope: at or under \"Sources/Domain\". Remove this dependency or move the code outside this scope."
        ).matches).count == 1)
    }
}

@Test func ownershipFindsUnownedAndOverlappingEmptyFiles() throws {
    let harness = RuleTestHarness(SourceOwners.self)
    #expect(try harness.evaluate([
        .swift("Sources/Domain/Model.swift", source: ""),
        .swift("Sources/UI/Screen.swift", source: ""),
        .swift("Tests/Fixture.swift", source: ""),
    ]).isEmpty)
    let failing = try harness.evaluate([
        .swift("Sources/Unowned/New.swift", source: ""),
        .swift("Sources/UI/Shared/Shared.swift", source: ""),
    ])
    #expect(failing.count == 2)
    for (path, count) in [("Sources/Unowned/New.swift", 0), ("Sources/UI/Shared/Shared.swift", 2)] {
        #expect(failing.filter(ViolationMatcher(
            id: "boundary.owners", path: path, line: 1, column: 1,
            reason: count == 0
                ? "This file has no source owner. Owner scopes: at or under \"Sources/Domain\", at or under \"Sources/UI\", at or under \"Sources/UI/Shared\". Move the file into an owner scope or add its intended owner."
                : "This file matches 2 source owners: at or under \"Sources/UI\", at or under \"Sources/UI/Shared\". Narrow these scopes until the file has exactly one owner."
        ).matches).count == 1)
    }
}

@Test func missingMatchesDoNotHideInvalidOwnerPaths() {
    #expect(throws: BumperError.self) {
        try RuleTestHarness(InvalidOwners.self).evaluate([.swift("Tests/Fixture.swift", source: "")])
    }
    #expect(throws: BumperError.self) {
        try RuleTestHarness(InvalidImportOwner.self).evaluate([.swift("Sources/Fixture.swift", source: "")])
    }
}

private enum NetworkOwnership: SyntaxRule {
    static let metadata = RuleMetadata(id: "boundary.network", summary: "Network has one boundary")
    static var body: SyntaxCheck {
        Rules.importOwnership(["Network"], allowed: .under("Sources/Transport").union(.files(["Sources/TLS.swift"])))
    }
}

private enum DomainImports: SyntaxRule {
    static let metadata = RuleMetadata(id: "boundary.domain", summary: "Keep UI out of domain models")
    static var body: SyntaxCheck {
        Rules.forbiddenImports(["UIKit", "SwiftUI"], scope: .under("Sources/Domain"))
    }
}

private enum SourceOwners: SyntaxRule {
    static let metadata = RuleMetadata(id: "boundary.owners", summary: "Every source has one owner")
    static var body: SyntaxCheck {
        Rules.sourceOwnership([
            .under("Sources/Domain"), .under("Sources/UI"), .under("Sources/UI/Shared"),
        ], scope: .under("Sources"))
    }
}

private enum InvalidOwners: SyntaxRule {
    static let metadata = RuleMetadata(id: "boundary.invalid_owners", summary: "Validate owners even without subjects")
    static var body: SyntaxCheck { Rules.sourceOwnership([.under("../External")], scope: .under("Sources")) }
}

private enum InvalidImportOwner: SyntaxRule {
    static let metadata = RuleMetadata(id: "boundary.invalid_import", summary: "Validate owners even without imports")
    static var body: SyntaxCheck { Rules.importOwnership(["Network"], allowed: .files(["../External.swift"])) }
}

@Test func repairMessagesPreserveExcludedAndCustomScopes() throws {
    let harness = RuleTestHarness(RestrictedNetworkOwner.self)
    #expect(try harness.evaluate([.swift("Sources/Transport.swift", source: "import Network")]).isEmpty)
    let failing = try harness.evaluate([.swift("Sources/Domain/Model.swift", source: "import Network")])
    #expect(failing.count == 1)
    #expect(failing.filter(ViolationMatcher(
        id: "boundary.restricted_network", path: "Sources/Domain/Model.swift", line: 1, column: 1,
        reason: "Import Network is outside its allowed boundary. Allowed locations: (at or under \"Sources\") except (at or under \"Sources/Domain\"). Move the code that needs this import to an allowed location."
    ).matches).count == 1)
    #expect(RuleScope.files(["B.swift", "A.swift"]).description == "\"A.swift\", \"B.swift\"")
    #expect(RuleScope.files([]).description == "no files")
    #expect(RuleScope { _ in true }.description == "a custom scope")
}

private enum RestrictedNetworkOwner: SyntaxRule {
    static let metadata = RuleMetadata(id: "boundary.restricted_network", summary: "An exclusion remains excluded in the repair")
    static var body: SyntaxCheck {
        Rules.importOwnership(["Network"], allowed: .under("Sources").excluding(.under("Sources/Domain")))
    }
}
