import BumperBowlingCore
import SwiftSyntax

let parsingBoundary = Rules.boundaryOnly(
    function: "Parser.parse",
    allowed: .files([
        "Sources/BumperBowlingCore/SourceFileContext.swift",
        "Sources/BumperBowlingCore/SwiftFileParser.swift",
    ]),
    id: "bumper.parsing_boundary"
)

let processConstructionBoundary = Rules.canonicalConstruction(
    "Process",
    owners: .files(["Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"]),
    id: "bumper.process_construction"
)

// These method spellings stay in the runner's bounded or interactive path.
let processExecutionBoundary = Rules.files(
    "bumper.process_execution",
    summary: "Launch and wait only in ConfigurationLoader.runProcess or runSwiftTests.",
    scope: .files(["Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"])
) { file in
    functionCalls().matches(in: file).compactMap { call in
        guard let member = call.node.calledExpression.as(MemberAccessExprSyntax.self),
              ["run", "launch", "waitUntilExit"].contains(member.declName.baseName.text) else { return nil }
        if let function = call.node.ancestors.compactMap({ $0.as(FunctionDeclSyntax.self) }).first,
           ["runProcess", "runSwiftTests"].contains(function.name.text),
           function.bumper.lexicalContext.placement == .typeMember,
           function.bumper.lexicalContext.enclosingNominalNames == ["ConfigurationLoader"] {
            return nil
        }
        return call.failure(
            message: "Launch and wait only in ConfigurationLoader.runProcess or runSwiftTests.",
            evidence: ViolationEvidence(
                observed: call.node.trimmedDescription,
                expectation: "direct process execution stays in the bounded or interactive helper"
            )
        )
    }
}

let immutableEngineState = Rules.files(
    "bumper.immutable_engine_state",
    summary: "Mutable stored state belongs only to the output buffer, syntax visitors, and fact cache.",
    scope: .under("Sources/BumperBowlingCore")
) { file in
    let mutableOwners: [RelativeFilePath: String] = [
        "Sources/BumperBowlingCore/ConfigurationCommandRunner.swift": "BoundedOutputBuffer",
        "Sources/BumperBowlingCore/SwiftFileParser.swift": "SourceVisitor",
        "Sources/BumperBowlingCore/SyntaxQuery.swift": "SyntaxNodeCollector",
        "Sources/BumperBowlingCore/FactProviders.swift": "FactStore",
    ]
    return variables().matches(in: file).compactMap { variable in
        guard variable.node.bumper.isMutableBinding,
              !variable.node.bumper.storedProperties().isEmpty else { return nil }
        let owners = variable.node.bumper.lexicalContext.enclosingNominalNames
        if let allowed = mutableOwners[file.path], owners == [allowed] { return nil }
        return variable.failure(
            message: "Mutable stored state belongs only to the output buffer, syntax visitors, and fact cache.",
            evidence: ViolationEvidence(
                observed: "var \(variable.node.bumper.bindingNames.joined(separator: ", ")) in \(owners.first ?? "file scope")",
                expectation: "immutable stored state outside the four named implementation declarations"
            )
        )
    }
}
