# SwiftSyntax Surface

Bumper Bowling validates declared codebase shape against selected SwiftSyntax nodes.

SwiftSyntax can represent the full Swift source tree. Bumper Bowling does not
copy that tree and does not expose an infinitely configurable query language. It
records source-accurate syntax nodes plus selected computed facts, projects them
into `ArchitectureGraph`, then runs lean mathematical checks over that graph.

Bumper Bowling also does not duplicate SwiftSyntax's type universe. The raw syntax vocabulary is SwiftSyntax's own `SyntaxKind`; richer local facts are computed as extensions over concrete SwiftSyntax nodes through `node.bumper`.

## Current Facts

### Files

- Relative file path.
- Owning component, derived from configured path ownership.

### Imports

- Explicit imported module names.
- Module import edges from source file to imported module.
- Component import edges when an imported module maps to a configured component.

### Declarations

- Syntactic `public` and `open` declarations.
- Declaration kind: actor, class, enum, function, protocol, struct, variable.
- Declaration name.
- Attribute names attached to public declarations.

### Stored Properties

- Stored property name.
- Explicit type annotation, when present.
- Mutability from `let` or `var`.

No type inference is performed. A stored property without an explicit type annotation does not have a known type fact.

### Enums

- Enum declaration names.
- Used by state-machine assertions such as requiring parser files to declare an enum whose name ends in `State`.

### Imperative Constructs

Bumper Bowling currently computes selected imperative facts from syntax nodes:

- assignment
- loop
- mutable binding
- `inout` expression
- `mutating` declaration

These facts are descriptive. They become policy only when a configuration declares a lane such as:

```swift
Disallows(.assignment, .loop, .mutableBinding)
```

### Syntax Kind Catalog

Bumper Bowling records the `SyntaxKind` values observed while walking each Swift source file.

Examples:

- `.sourceFile`
- `.importDecl`
- `.structDecl`
- `.variableDecl`
- `.identifierType`
- `.stringLiteralExpr`
- `.forceUnwrapExpr`

These remain SwiftSyntax values, not Bumper Bowling copies. A raw syntax-kind assertion looks like:

```swift
RequireSyntax(.enumDecl)
DisallowSyntax(.forceUnwrapExpr)
DoesNot(ContainSyntax(.forceUnwrapExpr), severity: .error)
```

This is set math over `SourceFileFacts.syntaxNodes.nodeKinds`.

For consumers that need syntax nodes Bumper Bowling does not name as built-in
rules, `ContainSyntaxNode` exposes matching over recorded SwiftSyntax node kind,
spelling, parent kind, and ancestor kind:

```swift
DoesNot(
    ContainSyntaxNode(
        SyntaxNodeMatcher(
            kind: .attribute,
            spelling: .exact("available")
        )
    ),
    severity: .error
)
```

Built-in syntax assertions are still projected-fact checks. They evaluate
observed syntax nodes and their immediate recorded context rather than executing
arbitrary tree queries. For repository-specific tree walks, use
`CustomSyntaxRule`, which receives a `SourceFileContext` with raw
`SourceFileSyntax`.

### Computed SwiftSyntax Views

When a rule needs more than kind membership, Bumper Bowling composes over real SwiftSyntax node types with computed views:

```swift
variableDecl.bumper.kind
variableDecl.bumper.isMutable
variableDecl.bumper.bindingNames
variableDecl.bumper.explicitTypeNames
variableDecl.bumper.storedProperties
```

These views add no stored state to SwiftSyntax nodes. They infer local facts from the node and, when needed, its syntax context.

## Configured Facts

The configuration supplies the facts SwiftSyntax cannot know by itself:

- included paths
- excluded paths
- component names
- component path ownership
- component module aliases
- allowed component dependency edges
- forbidden component dependency edges
- allowed capabilities
- assertion severities
- scoped modeling assertions

## Graph Projection

`ArchitectureGraph` is the evidence surface rules operate on. It currently contains:

- source files
- component nodes
- module import edges
- component import edges

Source files carry their observed imports, declarations, stored properties, enum names, imperative constructs, and syntax kind catalog.

Rules operate on that projection with deterministic operations: path scope, set membership, graph edge checks, and cycle detection.

Semantic shorthand does not add hidden facts. It composes `SourceFactRule` atoms, then lowers into these same graph operations.

## Not Known

Bumper Bowling does not know:

- inferred types
- symbol resolution
- overload resolution
- true build target membership
- macro expansion semantics
- compiler-validated public API surface
- protocol conformance truth
- runtime behavior
- data flow or effect flow
- business invariants

If a rule needs those facts, it does not belong in the SwiftSyntax-only lane.

Facts that could become useful with type-checked compiler help are tracked in [COMPILER_REQUESTS.md](COMPILER_REQUESTS.md).

## Rule

Every finding should have evidence:

```text
observed graph fact + declared lane = mismatch
```

If Bumper Bowling cannot show the observed fact, it should not report the violation.
