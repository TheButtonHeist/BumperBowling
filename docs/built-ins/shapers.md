# Standard Rule Shapers

[Built-ins index](README.md)

Standard shapers are ordinary `RuleDefinition` factories. They use the public
fact and query interfaces listed in this catalog.

Every standard shaper accepts a custom rule ID and severity. Each shaper has a
stable default ID and uses `.error` by default.

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
    ["shared", "replaceShared"],
    allowed: .under("Sources/Application")
)
```

This rule reports matching member-access spellings outside the allowed scope.
It reads `BuiltInFacts.memberReferences`.

Example finding: `shared is referenced outside its allowed owners.`

## Declaration, Access, and Type Policies

`Rules.declarationOwnership([.suffix("Receipt")], allowed: ...)` restricts
matching nominal declarations, functions, variables, and type aliases to one
scope. `Rules.publicAPIOwnership(allowed:)` and `Rules.spiOwnership(allowed:)`
restrict public/open and `@_spi` declarations respectively. For explicit type
syntax, `Rules.disallowTypeReferences("Any", in: ...)` covers signatures,
locals, and aliases. `Rules.maximumStoredProperties(matching: "Bool",
maximum: 1, in: ...)` provides syntax-first bool-soup/optional-bag pressure.
`Rules.stateMachineShape(in:requiresAssociatedValueCase:)` adds scoped state
enum and associated-value-case checks without replacing `.enumStateMachine`.

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

## Canonical Construction

```swift
Rules.canonicalConstruction(
    "InterfaceGraph",
    owners: .under("Sources/Builders")
)
```

This name expresses canonical-value ownership. Its implementation delegates to
`constructionOwnership`.

Example finding: `InterfaceGraph is constructed outside its allowed owners.`

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

It reads `BuiltInFacts.recursiveCallGroups`. That fact starts with
`functions()` and derives a locally dispatched call graph.

Example finding: `search recursively traverses Tree.branch outside its owners.`

Read [Build An Architecture Rule From The Ground Up](../RULE_FROM_THE_GROUND_UP.md)
for the complete composition.

## Single Nominal Spelling

```swift
Rules.singleNominalSpelling(
    suffix: "Expr",
    owner: .under("Sources/Plans")
)
```

This rule reports matching nominal declarations outside the owner scope. It
reads `BuiltInFacts.nominalTypes`.

Example finding: `CallExpr is declared outside the Expr owner scope.`

Next: [Rule factories](rule-factories.md)
