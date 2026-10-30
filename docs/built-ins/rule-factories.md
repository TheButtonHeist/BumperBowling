# Rule Factories

[Built-ins index](README.md)

These factories turn repository code into `RuleDefinition` values.

| Factory | Evaluation |
| --- | --- |
| `Rules.repository` | Runs once with a `RuleContext`. |
| `Rules.files` | Runs once for each parsed file in scope. |
| `Rules.each` | Runs once for each typed syntax match in scope. |
| `Rules.assert` | Counts matches per file or across the selected repository files. |
| `Rules.forbid` | Reports every match from a `SyntaxPattern`. |
| `Rules.visitor` | Runs a raw `SyntaxVisitor` and collects its failures. |

## Repository Rule

```swift
Rules.repository(
    "project.no_uikit",
    summary: "The repository does not import UIKit."
) { context in
    try context.facts(BuiltInFacts.imports).occurrences
        .filter { $0.module.rawValue == "UIKit" }
        .map {
            RuleFailure(
                path: $0.path,
                message: "UIKit is not allowed here."
            )
        }
}
```

## File Rule

```swift
Rules.files(
    "project.no_target_aliases",
    summary: "Target has one spelling."
) { file in
    typeAliases()
        .aliasing("Target")
        .matches(in: file)
        .map { $0.failure(message: "Target has an alternate alias.") }
}
```

## Match Rule

`Rules.each` accepts any public `SyntaxPattern`, including `SyntaxQuery<Node>`
for any SwiftSyntax node type. Its closure receives the existing
`SyntaxMatch<Node>` and returns zero or more failures. A thrown error aborts
analysis through the existing evaluator.

The [feature recipe](../RULE_RECIPES.md#requirements-inside-each-type) uses this
factory to inspect direct members of each selected declaration.

`Rules.each` evaluates existing matches. Use `Rules.assert` to require a match.

## Cardinality Rule

```swift
Rules.assert(
    functions().named("reduce"),
    cardinality: .exactly(1),
    id: "feature.one_reducer",
    summary: "Each feature file declares one reducer.",
    scope: .under("Sources/Features")
)
```

Available cardinalities are `.none`, `.atLeast(_)`, `.atMost(_)`, and
`.exactly(_)`. Counts must be nonnegative.

The default `counting: .perFile` preserves independent counts for each file.
The `scope` parameter selects files. It does not change the counting unit.

```swift
Rules.assert(
    structs().filter { $0.node.name.text == "AppEnvironment" },
    cardinality: .exactly(1),
    counting: .repository,
    id: "app.one_environment",
    summary: "The selected files declare one AppEnvironment.",
    scope: .under("Sources/App")
)
```

Repository counting combines matches from all selected files. Files use
lexical path order, and each pattern retains its match order within a file.
Excess matches retain their own paths and locations.

A shortage has count evidence and no source location. With repository
counting, its report path is the first selected file in lexical path order.
This file anchors the report. It is not necessarily the repair location.
Custom messages can inspect `violation.counting`.

A positive requirement over an empty file scope throws
`RuleEvaluationError.emptyRuleScope`. This applies to both counting modes.
Zero requirements permit an empty scope. Negative counts throw
`RuleEvaluationError.invalidSyntaxCardinality`.

## Forbidden Pattern

```swift
Rules.forbid(
    typeAliases().aliasing("UserID"),
    id: "identity.one_spelling",
    summary: "UserID has one spelling.",
    message: { match in
        "\(match.node.name.text) aliases UserID."
    }
)
```

## Raw Visitor

```swift
Rules.visitor(
    "project.no_force_unwrap",
    summary: "Production code handles optional absence.",
    scope: .productionSources
) { file in
    ForceUnwrapVisitor(file: file)
}
```

The visitor conforms to `SyntaxVisitor` and `RuleFailureSource`.

Next: [Syntax queries](syntax-queries.md)
