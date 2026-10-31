# Bumper Bowling Vocabulary

## Contents

- [Core Types](#core-types)
- [Composition Model](#composition-model)
- [Architecture DSL](#architecture-dsl)
- [Standard Rules Shapers](#standard-rules-shapers)
- [Typed Facts](#typed-facts)
- [Typed Queries And Per-File Rules](#typed-queries-and-per-file-rules)
- [Scopes And Typed Views](#scopes-and-typed-views)
- [Raw Visitor Escape Hatch](#raw-visitor-escape-hatch)

## Core Types

- `RuleDefinition`: metadata, scope, and `evaluate(in:)`.
- `RuleContext`: immutable configuration, parse-once repository syntax, and
  memoized facts.
- `RuleFailure`: one project-rule finding. The engine attaches metadata to
  produce a `RuleViolation` in a `RuleReport`.
- `RuleSet`: ordered `RuleDefinition` values.
- `FactProvider`: typed, memoized repository derivation.
- `RuleScope`: `.repository`, `.under(path)`, `.component(id)`,
  `.files(paths)`, or a predicate.
- `ComponentShape` / `AssertionShape`: reusable Architecture DSL policy.

## Composition Model

Small source requirements become repository vocabulary:

```swift
extension ComponentRequirement {
    static let valueModel = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}
```

Component shapes combine requirements, capabilities, and other shapes:

```swift
extension ComponentShape {
    static let foundationOnly = ComponentShape {
        MayUse(.foundation)
        DoesNotUse(.uiKit, .testing)
    }

    static let domain = ComponentShape {
        Applies(.foundationOnly)
        Requires(.valueModel)
    }
}
```

Apply a shape to each component that uses the vocabulary:

```swift
Component(.catalog) {
    Owns("Sources/Catalog")
    Applies(.domain)
}
```

Group heterogeneous rules with `RuleSet`:

```swift
let identityRules = RuleSet {
    Rules.singleDeclaration("UserID", owner: "Sources/Identity")
    Rules.noAlternateAliases("UserID")
}

Rules {
    identityRules
}
```

Custom `FactProvider` values can request other providers. `SyntaxQuery` values
compose filters, transforms, file scopes, and lexical scopes. Every path ends
in a `RuleDefinition` evaluated by the same engine.

## Architecture DSL

```swift
import BumperBowlingCore

enum AppComponent: String, ComponentKey {
    case core
}

let bumper = BumperProject {
    Architecture(AppComponent.self) {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
            MayUse(.foundation)
            Requires(.immutableStoredState, severity: .error)
        }
    }

    Rules {
        DependencyBoundaries(.error)
        Rules.singleDeclaration("AppModel", owner: "Sources/Core")
    }
}
```

## Standard `Rules` Shapers

Prefer these before writing a closure rule. Each accepts optional `id:` and
`severity:` arguments.

| Shaper | Purpose |
| --- | --- |
| `Rules.importOwnership(_:allowed:)` | Selected imports stay inside their owners. |
| `Rules.memberReferenceOwnership(_:allowed:)` | Selected member references stay inside their owners. |
| `Rules.singleDeclaration(_:owner:)` | One declaration under its owner path. |
| `Rules.constructionOwnership(_:allowed:)` | Construction only in the allowed scope. |
| `Rules.boundaryOnly(function:allowed:)` | Function calls only in a boundary scope. |
| `Rules.noAlternateAliases(_:allowing:)` | No aliases outside the allowing scope. |
| `Rules.canonicalTraversal(root:structuralCase:owners:)` | Recursive traversal stays with its owners. |

Symbols and paths are typed values with string-literal authoring:

```swift
Rules.canonicalTraversal(
    root: "SyntaxTree",
    structuralCase: "container",
    owners: .under("Sources/Traversal")
)
```

## Typed Facts

Use `Rules.repository(_:severity:summary:_:)`. Request facts with
`context.facts(_:)`. Providers derive at most once per evaluation.

```swift
Rules.repository(
    "project.no_uikit",
    severity: .error,
    summary: "The repository does not import UIKit."
) { context in
    try context.facts(BuiltInFacts.imports).occurrences
        .filter { $0.module.rawValue == "UIKit" }
        .map {
            RuleFailure(path: $0.path, message: "UIKit is not allowed here.")
        }
}
```

Current `BuiltInFacts` providers:

- `sourceFiles`, `imports`, `declarations`, `nominalTypes`, `extensions`
- `storedProperties`, `syntaxNodes`, `functionCalls`, `directRecursion`
- `recursiveCallGroups`, `effectiveAccess`, `enclosingDeclarations`
- `memberReferences`, `componentDependencies`

Define a provider only when no built-in provider or composition supplies the
fact:

```swift
struct DeclarationsPerFile: FactProvider {
    let id: FactProviderID = "project.declarations_per_file"

    func derive(in context: FactDerivationContext) throws
        -> [RelativeFilePath: Int] {
        let occurrences = try context.facts(BuiltInFacts.declarations).occurrences
        return Dictionary(grouping: occurrences, by: \.path).mapValues(\.count)
    }
}
```

## Typed Queries And Per-File Rules

`Rules.files(_:severity:summary:_:)` evaluates each selected parsed file. Query roots
are `functions()`, `initializers()`, `variables()`, `typeAliases()`,
`structs()`, `macroExpansions()`, `nominalDeclarations()`, and `functionCalls()`.

```swift
Rules.files(
    "project.no_target_alias",
    summary: "TargetQuery has one spelling."
) { file in
    typeAliases()
        .aliasing(NominalSymbol("TargetQuery"))
        .matches(in: file)
        .map { match in
            match.failure(message: "TargetQuery must not be aliased.")
        }
}
```

Use query operations such as `taking(_:)`, `callingSelf()`, `aliasing(_:)`,
`inheriting(_:)`, and `excluding(_:)` to retain the concrete SwiftSyntax node type.

Use `Rules.assert` for per-file cardinality:

```swift
Rules.assert(
    functions().named("reduce"),
    cardinality: .exactly(1),
    id: "feature.one_reducer",
    summary: "Each feature file declares one reducer.",
    scope: .under("Sources/Features")
)
```

Use `Rules.forbid` when every query match is a violation:

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

## Scopes And Typed Views

`RuleScope` selects files. Compose `.repository`, `.productionSources`,
`.component(_:)`, `.under(_:)`, and `.files(_:)` with union, intersection, or
exclusion.

`SyntaxScope` selects nodes inside a file. Use `.fileScope`, `.typeMembers`,
`.local`, `.protocolMembers`, `.enclosed(in:)`, and
`.insideFunction(matching:)` through `lexically(within:)` or
`lexically(excluding:)`.

`BumperSyntaxView` exposes value-only facts without discarding the concrete
SwiftSyntax node type. `TypeShape` describes explicit type spelling, referenced
type names, function shape, and attributes.

## Raw Visitor Escape Hatch

Use `Rules.visitor(...)` when the visitor owns arbitrary analysis and failure
collection. The visitor must conform to `RuleFailureSource`.

```swift
import SwiftSyntax

let noForceUnwrap = Rules.visitor(
    "project.no_force_unwrap",
    severity: .error,
    scope: .under("Sources"),
    summary: "Production code handles optional absence explicitly."
) { file in
    ForceUnwrapVisitor(file: file)
}

final class ForceUnwrapVisitor: SyntaxVisitor, RuleFailureSource {
    private let file: SourceFileContext
    private(set) var failures: [RuleFailure] = []

    init(file: SourceFileContext) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(
        _ node: ForceUnwrapExprSyntax
    ) -> SyntaxVisitorContinueKind {
        failures.append(
            file.failure(at: node, message: "Force unwrap is not allowed.")
        )
        return .visitChildren
    }
}
```

`VisitorRule` is the concrete rule type returned by this factory. Raw visitors
remain supported. The escalation gate controls when to use them.

## Query Relationships

Queries select typed syntax, then refine, navigate, and relate matches.
Use `matches(within:)` for strict descendants and `members(of:)` for declarations
in one direct member block. Use `containing(pattern)` for required descendants
and `without(inSameFile:)` for missing companions. Both retain the original
subject for diagnostics. Named declaration matches expose `name` directly.

Use the existing `Rules.forbid`, `assert`, and `each` factories with these queries.
Keep cross-file inventories in `DerivedFact` and repository rules. Read the
[query catalog](../../../docs/built-ins/syntax-queries.md) for exact boundaries.
