# Component Requirements

[Built-ins index](README.md)

A `ComponentRequirement` is a set of `SourceFactRule` values. Requirements
compose by set union.

## Stored-Property Requirements

| Requirement | Validation | Example failure |
| --- | --- | --- |
| `.noAnyStoredProperties` | A stored property does not have the explicit type `Any`. | `let value: Any` |
| `.noBroadExistentialStoredProperties` | A stored property type does not start with `any`. | `let service: any Service` |
| `.noBoolStoredProperties` | A stored property does not have the explicit type `Bool`. | `let isReady: Bool` |
| `.noOptionalStoredProperties` | A stored property does not use optional type syntax. | `let value: Payload?` |
| `.noRawStringStoredProperties` | An `Identifiable` `id` property does not use `String`. | `let id: String` |
| `.noStoredProperties` | The selected files contain no stored properties. | `let value: Payload` |
| `.immutableStoredState` | A stored property does not use `var`. | `var value: Payload` |
| `.enumStateMachine` | Each selected file declares an enum whose name ends in `State`. | A parser file has no state enum. |

Apply one or more requirements:

```swift
Component(.domain) {
    Owns("Sources/Domain")
    Requires(
        .noAnyStoredProperties,
        .immutableStoredState
    )
}
```

These are opt-in conventions. The enum-state requirement applies per selected
file. For a requirement about each type, use `Rules.each` and the
[per-declaration recipe](../RULE_RECIPES.md#3-requirements-inside-each-declaration).
A syntax shape does not establish runtime state-machine behavior.

## Composed Requirements

These conveniences only combine the primitives above.

| Requirement | Exact composition |
| --- | --- |
| `.explicitDomainSurfaces` | `.noAnyStoredProperties` and `.noBroadExistentialStoredProperties` |
| `.typedIdentity` | `.noRawStringStoredProperties` |
| `.computedState` | `.noStoredProperties` |
| `.swiftBasics` | `.explicitDomainSurfaces`, `.typedIdentity`, and `.immutableStoredState` |
| `.parserStateMachine` | `.enumStateMachine` |
| `.pureDomain` | `.swiftBasics` and `.functionalCore` |

`.functionalCore` disallows these `ImperativeConstruct` values:

- `.assignment`
- `.loop`
- `.mutableBinding`
- `.inoutExpression`
- `.mutatingDeclaration`

The separate `.directStringMatch` construct supports repository policy through
`Disallows` or `NoDirectStringMatching`.

Repositories define their own compositions in the same way:

```swift
extension ComponentRequirement {
    static let valueModel = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}
```

## Direct Syntax Requirements

| Helper | Adds |
| --- | --- |
| `RequireSyntax(.enumDecl)` | A required SwiftSyntax node kind. |
| `DisallowSyntax(.classDecl)` | A disallowed SwiftSyntax node kind. |
| `ContainSyntax(.enumDecl)` | A syntax-kind graph predicate for `Does` or `DoesNot`. |
| `ContainSyntaxNode(matcher)` | A detailed syntax-node predicate. |
| `Declare("State")` | A declaration predicate for `Does` or `DoesNot`. |
| `Declares("State")` | The short form of `Does(Declare("State"))`. |

`SyntaxNodeMatcher` matches any combination of node kind, spelling, parent
kind, and ancestor kind:

```swift
let unavailableAPI = SyntaxNodeMatcher(
    kind: .attribute,
    spelling: .contains("available"),
    ancestorKind: .structDecl
)

Component(.core) {
    Owns("Sources/Core")
    DoesNot(ContainSyntaxNode(unavailableAPI))
}
```

Next: [Graph assertions](assertions.md)
