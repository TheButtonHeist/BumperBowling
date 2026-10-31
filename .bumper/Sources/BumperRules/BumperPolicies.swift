import BumperBowlingCore
import SwiftSyntax

public struct ParsingBoundaryRule: SyntaxRule {
    public static let metadata = RuleMetadata(id: "bumper.parsing_boundary", summary: "Reuse SwiftLint's parsed syntax")
    public static var body: SyntaxCheck {
        Rules.forbid(functionCalls().filter { ["Parser.parse", "SwiftParser.Parser.parse"].contains($0.node.calleeName) }) { _ in
            "Reuse file.syntax instead of parsing again"
        }
    }
}

public struct ProcessConstructionRule: SyntaxRule {
    public static let metadata = RuleMetadata(id: "bumper.process_construction", summary: "Construct processes only in the command runner")
    public static var body: SyntaxCheck {
        Rules.forbid(
            functionCalls().filter { ["Process", "Foundation.Process", "Process.init", "Foundation.Process.init"].contains($0.node.calleeName) },
            scope: RuleScope.repository.excluding(.files(["Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"]))
        ) { _ in "Construct processes only in ConfigurationCommandRunner.swift" }
    }
}

public struct ProcessExecutionRule: SyntaxRule {
    public static let metadata = RuleMetadata(id: "bumper.process_execution", summary: "Use the bounded or interactive process helper")
    public static var body: SyntaxCheck {
        Rules.forEach(functionCalls().filter { call in
            call.node.calledExpression.as(MemberAccessExprSyntax.self).map {
                ["run", "launch", "waitUntilExit"].contains($0.declName.baseName.text)
            } ?? false
        }, scope: .files(["Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"])) { call in
            let function = call.node.ancestors.compactMap { $0.as(FunctionDeclSyntax.self) }.first
            let allowed = function.map {
                ["runProcess", "runSwiftTests"].contains($0.name.text)
                    && $0.parent?.is(MemberBlockItemSyntax.self) == true
                    && $0.enclosingNominalNames == ["ConfigurationLoader"]
            } ?? false
            Rules.require(allowed, at: call, message: "Launch and wait only in ConfigurationLoader.runProcess or runSwiftTests")
        }
    }
}

public struct ImmutableEngineStateRule: SyntaxRule {
    public static let metadata = RuleMetadata(id: "bumper.immutable_engine_state", summary: "Keep engine models immutable")
    public static var body: SyntaxCheck {
        Rules.forEach(variables().filter(\.isMutable).storedMembers(), scope: .under("Sources/BumperBowlingCore")) { variable in
            let owners = variable.node.enclosingNominalNames
            let exceptions: [String: Set<String>] = [
                "Sources/BumperBowlingCore/ConfigurationCommandRunner.swift": ["BoundedOutputBuffer"],
                "Sources/BumperBowlingCore/SyntaxQuery.swift": ["SyntaxNodeCollector"],
                "Sources/BumperBowlingCore/RuleDefinition.swift": ["RuleSettings", "NativeSyntaxRule", "NativeRepositoryRule"],
            ]
            let allowed = owners.count == 1 && exceptions[variable.file.path]?.contains(owners[0]) == true
            Rules.require(allowed, at: variable,
                          message: "Keep stored state immutable: \(variable.bindingNames.joined(separator: ", ")) in \(owners.first ?? "file scope")")
        }
    }
}
