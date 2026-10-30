import SwiftSyntax
import Testing
@testable import BumperBowlingCore

@Suite("Rule Examples")
struct RuleExampleTests {
    @Test
    func forbiddenImportExamples() async throws {
        try await assertRule(
            .forbiddenImport([
                RuleSetting(severity: .error, values: ["Testing"], paths: ["Sources/Core"]),
            ]),
            passing: SourceFixture("""
            import Foundation

            public struct ProductionModel {}
            """),
            failing: SourceFixture("""
            ↓import Testing

            public struct ProductionModel {}
            """),
            expectedMessages: [
                "core imports forbidden module Testing",
            ]
        )
    }

    @Test
    func componentBoundaryExamples() async throws {
        try await assertRule(
            .componentBoundary(.error),
            passing: SourceFixture("""
            import Foundation

            public struct CoreFeature {}
            """),
            failing: SourceFixture("""
            ↓import UI

            public struct CoreFeature {}
            """),
            expectedMessages: [
                "core imports undeclared component UI (ui)",
            ]
        )
    }

    @Test
    func duplicateOwnershipExamples() async throws {
        let passingConfiguration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", paths: ["Sources/Core"]),
            ]
        )
        let failingConfiguration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", paths: ["Sources/Core"]),
                ComponentConfiguration(name: "models", paths: ["Sources/Core/Models"]),
            ]
        )

        try await assertRule(
            .duplicateOwnership(.error),
            passing: SourceFixture(
                path: "Sources/Core/Models/Model.swift",
                """
                public struct Model {}
                """
            ),
            failing: SourceFixture(
                path: "Sources/Core/Models/Model.swift",
                """
                public struct Model {}
                """
            ),
            passingConfiguration: passingConfiguration,
            failingConfiguration: failingConfiguration,
            expectedMessages: [
                "models path Sources/Core/Models overlaps core path Sources/Core",
            ]
        )
    }

    @Test(arguments: [false, true])
    func declaredDependencyCycleExamples(selfDependency: Bool) async throws {
        let passingConfiguration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", paths: ["Sources/Core"], mayDependOn: ["ui"]),
                ComponentConfiguration(name: "ui", paths: ["Sources/UI"]),
            ]
        )
        let failingConfiguration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", paths: ["Sources/Core"], mayDependOn: selfDependency ? ["core"] : ["ui"]),
                ComponentConfiguration(name: "ui", paths: ["Sources/UI"], mayDependOn: ["core"]),
            ]
        )

        try await assertRule(
            .declaredDependencyCycle(.error),
            passing: SourceFixture("""
            public struct CoreFeature {}
            """),
            failing: SourceFixture("""
            public struct CoreFeature {}
            """),
            passingConfiguration: passingConfiguration,
            failingConfiguration: failingConfiguration,
            expectedMessages: [
                "Declared dependency cycle includes component core",
            ]
        )
    }

    @Test
    func storedPropertyIdentityExamples() async throws {
        try await assertRule(
            .storedProperties(
                StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    disallowances: [.rawStringIdentity]
                )
            ),
            passing: SourceFixture("""
            struct User {
                let id: UserID
                let name: String
            }

            extension User: Identifiable {}
            """),
            failing: SourceFixture("""
            struct User {
                ↓let id: String
                let name: String
            }

            extension User: Identifiable {}
            """),
            expectedMessages: [
                "Stored property id uses raw String",
            ]
        )
    }

    @Test(arguments: ["", " = 0 { willSet {} }", " = 0 { didSet {} }"])
    func storedPropertyTypeAndMutabilityExamples(observers: String) async throws {
        try await assertRule(
            .storedProperties(
                StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    disallowances: [.any, .broadExistential, .storedVar]
                )
            ),
            passing: SourceFixture("""
            protocol Service {}
            struct Payload {}
            struct ServiceBox {}

            struct Model {
                let payload: Payload
                let service: ServiceBox
            }
            """),
            failing: SourceFixture("""
            protocol Service {}

            struct Model {
                ↓var payload: Any\(observers)
                ↓let service: any Service
            }
            """),
            expectedMessages: [
                "Stored property payload is mutable",
                "Stored property payload uses Any",
                "Stored property service uses a broad existential",
            ]
        )
    }

    @Test
    func computedStateExamples() async throws {
        try await assertRule(
            .storedProperties(
                StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    disallowances: [.storedProperty]
                )
            ),
            passing: SourceFixture("""
            struct Person {
                var fullName: String {
                    "Ada Lovelace"
                }
            }
            """),
            failing: SourceFixture("""
            struct Person {
                ↓let fullName: String
            }
            """),
            expectedMessages: [
                "Stored property fullName is stored",
            ]
        )
    }

    @Test
    func syntaxConstructExamples() async throws {
        try await assertRule(
            .syntaxConstructs(
                SyntaxConstructRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    disallowedConstructs: [
                        .assignment,
                        .directStringMatch,
                        .inoutExpression,
                        .loop,
                        .mutableBinding,
                        .mutatingDeclaration,
                    ]
                )
            ),
            passing: SourceFixture("""
            public func reduced(_ value: Int) -> Int {
                value + 1
            }
            """),
            failing: SourceFixture("""
            func consume(_ values: inout [Int]) {}

            public struct Counter {
                ↓mutating func increment(_ values: inout [Int]) {
                    ↓var total = 0
                    ↓for value in values {
                        total ↓= total + value
                    }
                    consume(↓&values)
                }

                func isReady() -> Bool {
                    return ↓"ready" == "ready"
                }
            }
            """),
            expectedMessages: [
                "Uses imperative construct assignment",
                "Uses imperative construct directStringMatch",
                "Uses imperative construct inoutExpression",
                "Uses imperative construct loop",
                "Uses imperative construct mutableBinding",
                "Uses imperative construct mutatingDeclaration",
            ]
        )
    }

    @Test
    func syntaxKindExamples() async throws {
        try await assertRule(
            .syntaxKinds(
                SyntaxKindRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    requiredKinds: [.enumDecl],
                    disallowedKinds: [.forceUnwrapExpr]
                )
            ),
            passing: SourceFixture("""
            enum ParserState {
                case ready
            }

            public struct Parser {}
            """),
            failing: SourceFixture("""
            public struct Parser {
                func value(_ input: Int?) -> Int {
                    ↓input!
                }
            }
            """),
            expectedMessages: [
                "Missing required SwiftSyntax node kind enumDecl",
                "Uses disallowed SwiftSyntax node kind forceUnwrapExpr",
            ]
        )
    }

    @Test
    func publicDeclarationExamples() async throws {
        try await assertRule(
            .publicDeclarations(
                PublicDeclarationRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    requiredNames: [.exact("PublicAPI")],
                    disallowedNames: [.exact("bumperBowling")]
                )
            ),
            passing: SourceFixture("""
            public struct PublicAPI {}

            let internalValue = 1
            """),
            failing: SourceFixture("""
            ↓public let bumperBowling = 1
            """),
            expectedMessages: [
                "Missing required public declaration PublicAPI",
                "Public declaration bumperBowling is disallowed",
            ]
        )
    }

    @Test
    func enumStateMachineExamples() async throws {
        try await assertRule(
            .enumStateMachine(
                PathRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/**/*Parser.swift"]
                )
            ),
            passing: SourceFixture(
                path: "Sources/Core/ThingParser.swift",
                """
                enum ParserState {
                    case scanning
                }

                public struct ThingParser {}
                """
            ),
            failing: SourceFixture(
                path: "Sources/Core/ThingParser.swift",
                """
                ↓public struct ThingParser {}
                """
            ),
            expectedMessages: [
                "Parser file does not declare an enum state machine",
            ]
        )
    }
}
