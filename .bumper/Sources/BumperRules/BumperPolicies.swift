import BumperBowlingCore
import SwiftSyntax

public struct ParsingBoundaryRule: SyntaxRule {
    public var configuration = RuleSettings<Self>()
    public static let metadata = RuleMetadata(id: "bumper.parsing_boundary", summary: "Reuse SwiftLint's parsed syntax")
    public init() {}
    public var body: SyntaxCheck {
        Rules.forbid(functionCalls().filter { ["Parser.parse", "SwiftParser.Parser.parse"].contains($0.node.calleeName) }) { _ in
            "Reuse file.syntax instead of parsing again"
        }
    }
}

public struct ProcessConstructionRule: SyntaxRule {
    public var configuration = RuleSettings<Self>()
    public static let metadata = RuleMetadata(id: "bumper.process_construction", summary: "Construct processes only in the command runner")
    public init() {}
    public var body: SyntaxCheck {
        Rules.forbid(
            functionCalls().filter { ["Process", "Foundation.Process", "Process.init", "Foundation.Process.init"].contains($0.node.calleeName) },
            scope: RuleScope.repository.excluding(.files(["Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"]))
        ) { _ in "Construct processes only in ConfigurationCommandRunner.swift" }
    }
}

public struct ProcessExecutionRule: SyntaxRule {
    public var configuration = RuleSettings<Self>()
    public static let metadata = RuleMetadata(id: "bumper.process_execution", summary: "Use the bounded or interactive process helper")
    public init() {}
    public var body: SyntaxCheck {
        Rules.each(functionCalls(), scope: .files(["Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"])) { call in
            guard let member = call.node.calledExpression.as(MemberAccessExprSyntax.self),
                  ["run", "launch", "waitUntilExit"].contains(member.declName.baseName.text) else { return [] }
            if let function = call.node.ancestors.compactMap({ $0.as(FunctionDeclSyntax.self) }).first,
               ["runProcess", "runSwiftTests"].contains(function.name.text),
               function.parent?.is(MemberBlockItemSyntax.self) == true,
               function.enclosingNominalNames == ["ConfigurationLoader"] { return [] }
            return [call.failure(message: "Launch and wait only in ConfigurationLoader.runProcess or runSwiftTests")]
        }
    }
}

public struct ImmutableEngineStateRule: SyntaxRule {
    public var configuration = RuleSettings<Self>()
    public static let metadata = RuleMetadata(id: "bumper.immutable_engine_state", summary: "Keep engine models immutable")
    public init() {}
    public var body: SyntaxCheck {
        Rules.each(variables().filter(\.isMutable).storedMembers(), scope: .under("Sources/BumperBowlingCore")) { variable in
            let owners = variable.node.enclosingNominalNames
            let exceptions = [
                "Sources/BumperBowlingCore/ConfigurationCommandRunner.swift": "BoundedOutputBuffer",
                "Sources/BumperBowlingCore/SyntaxQuery.swift": "SyntaxNodeCollector",
                "Sources/BumperBowlingCore/RuleDefinition.swift": "RuleSettings",
            ]
            if let owner = exceptions[variable.file.path], owners == [owner] { return [] }
            return [variable.failure(message: "Keep stored state immutable: \(variable.bindingNames.joined(separator: ", ")) in \(owners.first ?? "file scope")")]
        }
    }
}
