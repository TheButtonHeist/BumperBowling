# Syntax Queries

[Built-ins index](README.md)

Every query returns typed `SyntaxMatch` values. `match.node` retains its
concrete SwiftSyntax node type.

## Query Roots

| Query | Match type |
| --- | --- |
| `functions()` | `FunctionDeclSyntax` |
| `initializers()` | `InitializerDeclSyntax` |
| `variables()` | `VariableDeclSyntax` |
| `typeAliases()` | `TypeAliasDeclSyntax` |
| `structs()` | `StructDeclSyntax` |
| `macroExpansions()` | `MacroExpansionExprSyntax` |
| `nominalDeclarations()` | Nominal `DeclSyntax` values |
| `functionCalls()` | `FunctionCallExprSyntax` |
| `SyntaxQuery<Node>()` | Any selected SwiftSyntax node type |

## Query Composition

| Operation | Result |
| --- | --- |
| `.filter { ... }` | Keeps matches that meet a predicate. |
| `.compactMap { ... }` | Changes the match node type. |
| `.within(ruleScope)` | Includes files in a `RuleScope`. |
| `.excluding(ruleScope)` | Excludes files in a `RuleScope`. |
| `.lexically(within: syntaxScope)` | Includes nodes in a `SyntaxScope`. |
| `.lexically(excluding: syntaxScope)` | Excludes nodes in a `SyntaxScope`. |

Typed capabilities add these operations:

| Query | Operation | Match |
| --- | --- | --- |
| `functions()` | `.named(_:)` | Functions with a matching base name. |
| `functions()` | `.taking(_:)` | Functions with a matching explicit parameter type. |
| `functions()` | `.callingSelf()` | Direct self-recursive functions. |
| `variables()` | `.storedMembers()` | Declarations with at least one stored member binding. |
| `typeAliases()` | `.aliasing(_:)` | Aliases with a matching explicit target spelling. |
| `structs()` | `.inheriting(_:)` | Structs with a matching inheritance-clause type. |
| `macroExpansions()` | `.named(_:)` | Macro expansions with a matching name. |

## Match Context And Facts

`SyntaxMatch` is the rule-authoring value. Common facts are available directly:

| Access | Meaning |
| --- | --- |
| `match.node` | The concrete SwiftSyntax node. |
| `match.file` | The source file and its location helpers. |
| `match.lexicalContext` | Lexical placement and enclosing declarations. |
| `variable.isMutable` | A variable declaration uses the `var` keyword. |
| `variable.bindingNames` | Identifier names from the declaration's bindings. |
| `match.failure(...)` | A diagnostic at the matched node's source location. |

These properties delegate to the existing syntax helpers. They do not resolve
compiler identity or infer runtime mutation.

```swift
Rules.each(
    variables().filter(\.isMutable).storedMembers(),
    id: "project.mutable_members",
    summary: "Models do not declare mutable stored members."
) { variable in
    [variable.failure(
        message: "Mutable state in \(variable.lexicalContext.enclosingNominalNames.joined(separator: ".")).",
        evidence: ViolationEvidence(
            observed: variable.bindingNames.joined(separator: ", "),
            expectation: "no mutable stored members"
        )
    )]
}
```

This is an example policy, not a default rule. The
[public-harness fixtures](../../Tests/BumperBowlingTestSupportTests/DownstreamExtensibilityTests.swift)
cover passing and failing declarations with source evidence.

`.storedMembers()` excludes globals, locals, and computed properties. It
retains stored properties with `willSet` or `didSet` observers. A declaration
with several stored bindings remains one match. Its `bindingNames` lists the
identifier bindings.

## Raw Node Helpers

`BumperSyntaxView` adds value-only syntax facts. Important views include:

- Variable binding names, mutability, membership, and explicit types
- `TypeShape` names, function shape, and attributes
- Lexical placement and enclosing declarations
- Typealias target shape
- Function-call spelling

Raw nodes in visitors and fact providers can still use `node.bumper`.
Uncommon syntax remains available through `match.node`. The match API uses
explicit properties, without dynamic member lookup or a second syntax model.

Read [the SwiftSyntax surface](../SWIFTSYNTAX_SURFACE.md) for the complete syntax
contract.

Next: [Scopes, matching, and severity](scopes-and-matching.md)
