# Syntax Queries

[Built-ins index](README.md)

Every query returns typed `SyntaxMatch` values. `match.node` retains its
concrete SwiftSyntax node type.

## How The Pieces Fit

A rule follows this sequence:

```text
select nodes -> refine matches -> navigate or relate -> assert -> report
```

| Category | API | Responsibility |
| --- | --- | --- |
| Select | `SyntaxQuery<Node>`, `structs()`, `functions()` | Find typed nodes in parsed syntax. |
| Refine | `filter`, `named`, `inheriting`, file and lexical scopes | Keep the matches relevant to the policy. |
| Navigate | `matches(within:)`, `members(of:)` | Search inside a matched node with an explicit boundary. |
| Relate | `containing`, `without(inSameFile:)` | Select subjects based on related syntax. |
| Assert | `Rules.forbid`, `assert`, `each`, `repository` | Turn matches, counts, or custom logic into a rule. |
| Report | `SyntaxMatch.failure`, existing rule diagnostics | Retain the subject's original source location. |

`SyntaxPattern` is the common protocol. Its associated `Match` type is a real
SwiftSyntax node type. `SyntaxQuery<Node>` implements that protocol and preserves
its node type through filters and relationships. `compactMap` changes the node
type explicitly. No type erasure or second syntax model is necessary.

File scope, structural navigation, and counting are separate choices.
`RuleScope` selects subject files. Navigation chooses a subtree or member block.
`SyntaxCounting` chooses per-file or repository counts. A same-file companion
query searches the subject's original file. It can apply its own filters.

## Design choices

The API borrows established ideas without adding another rule language:

- [Clang matchers](https://clang.llvm.org/docs/LibASTMatchers.html) compose typed
  structural matches. Bumper keeps SwiftSyntax types and ordinary Swift closures.
- [ArchUnit](https://www.archunit.org/userguide/html/000_Index.html#_the_lang_api)
  separates selection from requirements. Queries select; rule factories evaluate
  requirements and report failures. `Rules.each` handles custom requirements.
- [ESLint selectors](https://eslint.org/docs/latest/extend/selectors) distinguish
  children from descendants. Bumper makes direct members, strict descendants,
  and same-file companions explicit.
- [typescript-eslint](https://typescript-eslint.io/developers/custom-rules/#conditional-type-information)
  warns against silently changing behavior when type information becomes
  available. Bumper's syntax queries do not claim compiler-backed identity.

Empty selections need deliberate treatment. `Rules.forbid` has no failure when
nothing matches. `Rules.assert` can require a positive count; positive counts
over an empty scope fail. A filtered query alone cannot prove that subjects exist.

Reusable policy functions can return existing queries or rules. New protocols
are unnecessary unless callers need a new kind of composition. Built-in helpers
should remove repeated tree navigation, not prescribe application architecture.

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
| `.containing(pattern)` | Keeps each subject once if the pattern matches a strict descendant. |
| `.without(inSameFile: { subject in ... })` | Keeps subjects without a matching companion in their parsed file. |
| `.within(ruleScope)` | Includes files in a `RuleScope`. |
| `.excluding(ruleScope)` | Excludes files in a `RuleScope`. |
| `.lexically(within: syntaxScope)` | Includes nodes in a `SyntaxScope`. |
| `.lexically(excluding: syntaxScope)` | Excludes nodes in a `SyntaxScope`. |

Typed capabilities add these operations:

| Query | Operation | Match |
| --- | --- | --- |
| `functions()` | `.named(_:)` | Functions with a matching base name. |
| `functionCalls()` | `.named(_:)` | Calls with an exact normalized spelling, including dynamic string names. |
| `functions()` | `.taking(_:)` | Functions with a matching explicit parameter type. |
| `functions()` | `.callingSelf()` | Direct self-recursive functions. |
| `variables()` | `.storedMembers()` | Declarations with at least one stored member binding. |
| `typeAliases()` | `.aliasing(_:)` | Aliases with a matching explicit target spelling. |
| `structs()` | `.inheriting(_:)` | Structs with a matching inheritance-clause type. |
| `macroExpansions()` | `.named(_:)` | Macro expansions with a matching name. |

## Structural Navigation

```swift
let methods = functions().members(of: model)
let nestedMethods = functions().matches(within: model)
```

`members(of:)` selects declarations written directly in the owner's member
block. A nested type's methods cannot satisfy a requirement on its parent.
It applies when the pattern matches declaration nodes and the owner is a
`DeclGroupSyntax`, such as a struct, enum, class, or extension.

`matches(within:)` selects strict descendants, including nodes inside nested
types. The root itself never counts as its own descendant. Neither operation
combines extensions or evaluates conditional compilation and macro output.

Built-in `SyntaxQuery` roots search the supplied subtree directly. Filters,
scopes, and `compactMap` retain that subtree boundary. Closure-backed queries
can keep their existing file extraction; subtree matching filters those results.

Existing custom patterns need only implement `matches(in:)`. The protocol's
default `matches(within:)` filters their file matches to the original subtree.
Custom patterns can implement subtree matching when a direct search is useful.

## Relationships

```swift
let livePreviews = macroExpansions().named("Preview")
    .containing(functionCalls().named("Client.live"))

let missingPreviews = structs().inheriting("View")
    .without(inSameFile: { view in
        macroExpansions().named("Preview")
            .containing(functionCalls().named(view.name))
    })
```

Both operations retain the subject's type, source order, and location.
`containing` returns each matching subject once, regardless of the number of
related matches. It searches strict descendants, not adjacent code.

`without(inSameFile:)` evaluates a companion pattern for each subject. It can
use the subject's name or other facts. Separately parsed trees cannot supply
companions, even when their paths match. An empty companion result keeps the
subject; an empty subject selection stays empty. A separate cardinality rule
can require subjects to exist.

These are filters that compose with existing rule factories. `Rules.forbid`
reports missing-preview subjects at their declarations. A containing-call rule
reports the enclosing preview. No missing node or source location is invented.

Call matching uses existing spelling normalization: `Client().load()` matches
`Client.load`, and `self.load()` matches `load`. `other.load()` retains its
receiver. This does not resolve receiver types, aliases, or compiler identity.

Same-file companion queries can scan the file once per subject. For large
inventories or cross-file relationships, use `DerivedFact` with
`Rules.repository`. These helpers do not cache arbitrary query closures.

The [related recipes](../RULE_RECIPES.md#related-syntax-in-three-small-rules)
show complete rules and paired fixtures for these operations.

## Match Context And Facts

`SyntaxMatch` is the rule-authoring value. Common facts are available directly:

| Access | Meaning |
| --- | --- |
| `match.node` | The concrete SwiftSyntax node. |
| `match.name` | The name on a node that conforms to `NamedDeclSyntax`. |
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
