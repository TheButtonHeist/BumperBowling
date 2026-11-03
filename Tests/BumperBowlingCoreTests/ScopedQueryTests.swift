import BumperBowlingCore
import Foundation
import os
import SwiftLintFramework
import SwiftSyntax
import Testing

@Test(arguments: [true, false])
func `file scopes skip extraction before within and excluding queries`(including: Bool) {
    let selected = SourceFileContext(file: SwiftLintFile(contents: "func selected() {}"), root: FileManager.default.temporaryDirectory)
    let other = SourceFileContext(file: SwiftLintFile(contents: "func other() {}"), root: FileManager.default.temporaryDirectory)
    let scope = RuleScope { $0.source.contains("selected") }
    let calls = OSAllocatedUnfairLock(initialState: 0)
    let query = SyntaxQuery<FunctionDeclSyntax> { file in
        calls.withLock { $0 += 1 }
        return functions().matches(in: file)
    }
    let scoped = including ? query.within(scope) : query.excluding(scope)
    let excluded = including ? other : selected
    let included = including ? selected : other
    #expect(scoped.matches(in: excluded).isEmpty)
    #expect(scoped.matches(within: SyntaxMatch(node: excluded.syntax, file: excluded)).isEmpty)
    #expect(calls.withLock { $0 } == 0)
    #expect(scoped.matches(in: included).map(\.name) == [including ? "selected" : "other"])
    #expect(calls.withLock { $0 } == 1)
    #expect(scoped.matches(within: SyntaxMatch(node: included.syntax, file: included)).count == 1)
    #expect(calls.withLock { $0 } == 2)
}
