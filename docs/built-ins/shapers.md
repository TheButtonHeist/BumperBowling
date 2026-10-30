# Standard Rule Shapers

[Built-ins index](README.md)

Standard shapers are ordinary `RuleDefinition` factories. They use the public
fact and query interfaces listed in this catalog.

Every standard shaper accepts a custom rule ID and severity. Each shaper has a
stable default ID and uses `.error` by default. Multiple instances of one
factory need distinct project-specific IDs. The engine rejects duplicate IDs.

## Import Ownership

```swift
Rules.importOwnership(
    ["UIKit"],
    allowed: .under("Sources/App")
)
```

This rule reports matching imports outside the allowed `RuleScope`. It reads
`BuiltInFacts.imports`.

Example finding: `UIKit is imported outside its allowed owners.`

## Member-Reference Ownership

```swift
Rules.memberReferenceOwnership(
    ["unsafeHandle"],
    allowed: .under("Sources/Interop"),
    id: "interop.unsafe_handles"
)
```

This rule reports matching member-access spellings outside the allowed scope.
It reads `BuiltInFacts.memberReferences`.

This example reserves the spelling `unsafeHandle` for interop code. Every
receiver with that member spelling matches. It does not identify a particular
property or resolve the receiver type. Use an explicit query when receiver
syntax is part of the policy.

Example finding: `unsafeHandle is referenced outside its allowed owners.`

## Declaration, Access, and Type Policies

`Rules.declarationOwnership([.suffix("Receipt")], allowed: ...)` restricts
matching nominal declarations, functions, variables, and type aliases to one
scope. `Rules.publicAPIOwnership(allowed:)` and `Rules.spiOwnership(allowed:)`
restrict public/open and `@_spi` declarations respectively.

These access rules observe declarations through `BuiltInFacts.declarationContracts`,
including initializers, subscripts, enum cases, and protocol requirements.
Public extension defaults count even when the target type is in another file.
The access inventory describes written access and lexical defaults. It does not
resolve implicit override access or prove compiler visibility across modules.
SPI matching uses attributes written on each declaration. It does not infer
compiler visibility from SPI attributes on enclosing declarations.

`Rules.disallowTypeReferences("Any", in: ...)` reads explicit signature types,
member and local annotations, aliases, enum payloads, and associated-type defaults.
Inferred types, inheritance clauses, generic constraints, and compiler identity
are outside this inventory. Findings point to the explicit type syntax.

Per-declaration shape and count policies use `Rules.each`. The
[feature recipe](../RULE_RECIPES.md#3-requirements-inside-each-declaration) makes
both the selection and the counting unit explicit. No file-based model heuristic
is necessary.

## Single Declaration

```swift
Rules.singleDeclaration(
    "AppEnvironment",
    owner: "Sources/Application"
)
```

This rule requires exactly one matching nominal declaration under the owner
path. It reads `BuiltInFacts.declarations`.

Example findings report a missing declaration, another declaration, or a
declaration outside the owner path.

## Construction Ownership

```swift
Rules.constructionOwnership(
    "APIClient",
    allowed: .under("Sources/Networking")
)
```

This rule reports matching initializer calls outside the allowed scope. It
reads `BuiltInFacts.functionCalls`.

Example finding: `APIClient is constructed outside its allowed owners.`

## Boundary-Only Function Use

```swift
Rules.boundaryOnly(
    function: "JSONDecoder.decode",
    allowed: .under("Sources/Decoding")
)
```

This rule reports matching function calls outside the allowed scope. It reads
`BuiltInFacts.functionCalls`.

Example finding: `JSONDecoder.decode is called outside its boundary.`

## No Alternate Aliases

```swift
Rules.noAlternateAliases(
    "UserID",
    allowing: .under("Sources/Migration")
)
```

This rule reports matching `typealias` declarations outside the allowing
scope. It composes `typeAliases()`, `aliasing(_:)`, and a `SyntaxRule`.

Example finding: `AccountIdentifier aliases UserID.`

## Canonical Traversal

```swift
Rules.canonicalTraversal(
    root: "Tree",
    structuralCase: "branch",
    owners: .under("Sources/TreeTraversal")
)
```

This rule reports direct or mutual recursive traversal outside its owners. A
qualifying recursive group matches the structural case against a root-typed
parameter or `self`.

This is a specialized policy for projects that centralize recursive traversal.
It does not impose that design on other projects. Its graph uses local call
spellings, with no compiler identity or overload resolution.

It reads `BuiltInFacts.recursiveCallGroups`. That fact starts with
`functions()` and derives a locally dispatched call graph.

Example finding: `search recursively traverses Tree.branch outside its owners.`

Read [Build An Architecture Rule From The Ground Up](../RULE_FROM_THE_GROUND_UP.md)
for the complete composition.

The [nominal-name recipe](../RULE_RECIPES.md#an-explicit-nominal-name-query)
shows a project-owned suffix convention through an explicit nominal query.

Next: [Rule factories](rule-factories.md)
