import Testing
@testable import BumperBowlingCore

@Suite("Syntax capabilities")
struct SyntaxCapabilityTests {
    @Test
    func lexicalContextsAndScopesCompose() throws {
        let file = try sourceFile(
            """
            func fileLevel() {}

            struct Store {
                func load() {
                    func nested() {}
                }
            }

            extension Store {
                func save() {}
            }

            protocol Persisting {
                func persist()
            }
            """
        )

        let contexts = Dictionary(uniqueKeysWithValues: functions().matches(in: file).map { match in
            (match.node.name.text, match.lexicalContext)
        })
        #expect(contexts["fileLevel"]?.placement == .fileScope)
        #expect(contexts["load"]?.placement == .typeMember)
        #expect(contexts["nested"]?.placement == .local)
        #expect(contexts["nested"]?.enclosingFunctionName == "load")
        #expect(contexts["save"]?.enclosingExtensionName == "Store")
        #expect(contexts["persist"]?.isInsideProtocol == true)

        let storeMembers = SyntaxScope.typeMembers.intersecting(.enclosed(in: "Store"))
        #expect(functions().lexically(within: storeMembers).matches(in: file).map(\.node.name.text) == [
            "load",
            "save",
        ])
        #expect(functions().lexically(within: .protocolMembers).matches(in: file).map(\.node.name.text) == [
            "persist",
        ])
        #expect(functions().lexically(excluding: .local).matches(in: file).count == 4)
    }

    @Test
    func typeShapesExposeFunctionAttributesAndAliasSpellings() throws {
        let file = try sourceFile(
            """
            typealias Handler = (@Sendable (Payload) -> Void)?

            struct Store {
                let onChange: (@MainActor (Payload) -> Void)?
                let handler: Handler?
                let optionalHandler: Optional<Handler>
                let optionalFunction: Optional<() -> Void>
                let nestedCallback: (@Sendable () -> Void) -> Void
                let qualified: Module.Payload
            }
            """
        )

        let alias = try #require(typeAliases().matches(in: file).first)
        #expect(alias.node.bumper.aliasedTypeShape.isFunction)
        #expect(alias.node.bumper.aliasedTypeShape.hasAttribute(matching: "Sendable"))
        #expect(alias.node.bumper.aliasedTypeShape.references("Payload"))

        let variableMatches = variables().matches(in: file)
        let onChange = try #require(variableMatches.first { $0.bindingNames == ["onChange"] })
        let onChangeShape = try #require(onChange.node.bindings.first?.bumper.explicitTypeShape)
        #expect(onChangeShape.isFunction)
        #expect(onChangeShape.attributes == ["MainActor"])
        #expect(onChangeShape.outerFunctionAttributes == ["MainActor"])
        let handler = try #require(variableMatches.first { $0.bindingNames == ["handler"] })
        #expect(handler.node.bindings.first?.bumper.explicitTypeShape?.outerTypeName == "Handler")
        let optionalHandler = try #require(variableMatches.first {
            $0.bindingNames == ["optionalHandler"]
        })
        #expect(optionalHandler.node.bindings.first?.bumper.explicitTypeShape?.outerTypeName == "Handler")
        let optionalFunction = try #require(variableMatches.first {
            $0.bindingNames == ["optionalFunction"]
        })
        #expect(optionalFunction.node.bindings.first?.bumper.explicitTypeShape?.isFunction == true)
        let nestedCallback = try #require(variableMatches.first {
            $0.bindingNames == ["nestedCallback"]
        })
        let nestedShape = try #require(nestedCallback.node.bindings.first?.bumper.explicitTypeShape)
        #expect(nestedShape.attributes == ["Sendable"])
        #expect(nestedShape.outerFunctionAttributes.isEmpty)
        let qualified = try #require(variableMatches.first { $0.bindingNames == ["qualified"] })
        let qualifiedShape = try #require(qualified.node.bindings.first?.bumper.explicitTypeShape)
        #expect(qualifiedShape.references("Payload"))
        #expect(qualifiedShape.outerTypeName == "Payload")
    }

    private func sourceFile(_ source: String) throws -> SourceFileContext {
        SourceFileContext(
            descriptor: SourceFileDescriptor(
                path: "Sources/Core/Fixture.swift",
                component: try ComponentID("core")
            ),
            source: source
        )
    }
}
