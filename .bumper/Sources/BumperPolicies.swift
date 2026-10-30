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
let processExecutionBoundary = Rules.each(
    functionCalls(),
    id: "bumper.process_execution",
    summary: "Launch and wait only in ConfigurationLoader.runProcess or runSwiftTests.",
    scope: .files(["Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"])
) { call in
    guard let member = call.node.calledExpression.as(MemberAccessExprSyntax.self),
          ["run", "launch", "waitUntilExit"].contains(member.declName.baseName.text) else { return [] }
    if let function = call.node.ancestors.compactMap({ $0.as(FunctionDeclSyntax.self) }).first,
       ["runProcess", "runSwiftTests"].contains(function.name.text),
       function.bumper.lexicalContext.placement == .typeMember,
       function.bumper.lexicalContext.enclosingNominalNames == ["ConfigurationLoader"] {
        return []
    }
    return [call.failure(
        message: "Launch and wait only in ConfigurationLoader.runProcess or runSwiftTests.",
        evidence: ViolationEvidence(
            observed: call.node.trimmedDescription,
            expectation: "direct process execution stays in the bounded or interactive helper"
        )
    )]
}

private let mutableOwners: [RelativeFilePath: String] = [
    "Sources/BumperBowlingCore/ConfigurationCommandRunner.swift": "BoundedOutputBuffer",
    "Sources/BumperBowlingCore/SwiftFileParser.swift": "SourceVisitor",
    "Sources/BumperBowlingCore/SyntaxQuery.swift": "SyntaxNodeCollector",
    "Sources/BumperBowlingCore/FactProviders.swift": "FactStore",
]

let immutableEngineState = Rules.each(
    variables().filter(\.isMutable).storedMembers(),
    id: "bumper.immutable_engine_state",
    summary: "Mutable stored state belongs only to the output buffer, syntax visitors, and fact cache.",
    scope: .under("Sources/BumperBowlingCore")
) { variable in
    let owners = variable.lexicalContext.enclosingNominalNames
    if let allowed = mutableOwners[variable.file.path], owners == [allowed] { return [] }
    return [variable.failure(
        message: "Mutable stored state belongs only to the output buffer, syntax visitors, and fact cache.",
        evidence: ViolationEvidence(
            observed: "var \(variable.bindingNames.joined(separator: ", ")) in \(owners.first ?? "file scope")",
            expectation: "immutable stored state outside the four named implementation declarations"
        )
    )]
}
