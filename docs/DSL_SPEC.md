# Bumper Bowling Configuration Language Specification

Bumper Bowling's assertion surface is Swift. The configuration language is intentionally small and familiar to SwiftLint users, but its center is architecture snapshot testing: components own code, declare dependency edges and import capabilities, and require specific SwiftSyntax-observed facts.

Bumper Bowling exposes the configuration language through the `bumper` CLI. The CLI loads `BumperBowling.swift` for shell workflows, CI jobs, and product tests.

A configuration declares the shape the repository wants using Swift types. SwiftSyntax supplies what is visible in source. Bumper Bowling checks whether the observed graph facts satisfy the declared shape.

`bumper scan` shows the architecture graph the code currently expresses. The configuration declares the bounds; scan is evidence for those bounds.

The graph is intentionally not a second AST. It is a compact projection of facts Bumper Bowling rules can use, and it is the evidence trail for every finding.

The configuration compiles into typed architecture rules. Validation is deliberately lean math over the parsed graph: path scope, set membership, edge checks, and cycle detection.

Facts become rules when the configuration scopes them. The atom is
`SourceFactRule`; a `ComponentRequirement` is a composable set of those atoms.
Bumper Bowling includes small built-in requirement primitives and conveniences,
and repositories can define their own vocabulary:

```swift
extension ComponentRequirement {
    static let valueCore = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .computedState,
        .immutableStoredState,
        .functionalCore
    )
}
```

`Requires(.valueCore, severity: .error)` still lowers into raw graph checks over stored-property facts, syntax-construct facts, and enum facts.

Consumer-owned shape files can live under `.bumper/Sources`. Bumper Bowling
compiles those Swift files into the temporary configuration runner beside
`BumperBowling.swift`, then runs the resulting executable in the same sandboxed
evaluation path. This lets a repository define its own house vocabulary without
adding those names to Bumper Bowling itself:

```swift
// .bumper/Sources/HouseStyle.swift
import BumperBowlingCore

extension ComponentRequirement {
    static let domainCore = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}

extension ComponentShape {
    static let domain = ComponentShape {
        MayUse(.foundation)
        DoesNotUse(.uiKit, .testing)
        Requires(.domainCore, severity: .error)
    }
}

extension AssertionShape {
    static let global = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        SourceCoverage(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

```swift
// BumperBowling.swift
let bumper = BumperProject {
    Architecture {
        Component(.core) {
            Owns("Sources/Core")
            Applies(.domain)
        }
    }

    Rules {
        ApplyAssertions(.global)
    }
}
```

## Composition

Composition lets a repository define its own architecture language. Bumper
Bowling supplies the rule engine. The repository supplies the vocabulary and
policy that fit its codebase.

- `ComponentRequirement` groups source-fact requirements.
- `ComponentShape` groups component elements, such as capabilities,
  dependencies, and requirements.
- `AssertionShape` groups repository-level `RuleConfiguration` values.

`Applies(.domain)` inserts the elements from `.domain` into the current
component. It does not create a component, a scope, or an evaluator. The
component's `Owns(...)` paths provide the default scope for its requirements.

A shape can apply another shape. The component builder flattens the result
into one set of component elements. A shape does not add hidden facts or apply
rules because a file was imported.

Use the lower-level pieces when a reusable shape is not a good fit. Define a
`RuleDefinition` with a `RuleScope` for a repository-specific check. Built-in
and project-defined rules use the same parser, fact cache, and report format.

This composition model is Bumper Bowling's extension point. It gives each
repository typed, reusable policy without a plugin registry, dynamic rule
loading, or a second rule engine.

For shared local Swift packages, put a normal SwiftPM package at
`.bumper/Package.swift`. Bumper Bowling automatically adds that package to the
generated configuration runner and expects a `BumperRules` library product:

```text
.bumper/
  Package.swift
  Sources/BumperRules/Rules.swift
```

The package does not define or apply rules by convention alone. It only makes
Swift values importable; `BumperBowling.swift` still chooses what to use:

```swift
import BumperRules
```

Project rules are the escape hatch for repository-specific checks that cannot
be named ahead of time by Bumper Bowling. They are ordinary `RuleDefinition`
values added to the `Rules` block, evaluated by the same engine as built-ins:

```swift
let bumper = BumperProject {
    Architecture {
        Component(.score) {
            Owns("Sources/TheScore")
            Modules("TheScore")
        }
    }

    Rules {
        projectRules
    }
}
```

Fact-based project rules evaluate memoized typed facts:

```swift
// .bumper/Sources/ProjectRules.swift
import BumperBowlingCore

let projectRules = RuleSet {
    Rules.repository(
        "the_score.import_allow_list",
        severity: .error,
        summary: "TheScore imports only its value-layer dependencies."
    ) { context in
        let allowedImports = Set(["Foundation"])
        return try context.facts(BuiltInFacts.imports).occurrences
            .filter { !allowedImports.contains($0.module.rawValue) }
            .map { occurrence in
                RuleFailure(
                    path: occurrence.path,
                    message: "\(occurrence.component?.rawValue ?? "Unowned source") imports non-allowlisted module \(occurrence.module.rawValue)",
                    evidence: ViolationEvidence(
                        observed: occurrence.module.rawValue,
                        expectation: "allowed imports: Foundation"
                    )
                )
            }
    }
}
```

Bumper Bowling owns the scan. The host sends the scanned source files to the
cached project runner as Codable `RepositoryInput`; the runner parses each file
once, evaluates all rules, and returns one Codable `RuleReport`. Closures never
cross the process boundary, and rule code does not traverse the filesystem.

The scan includes all selected Swift sources. Component ownership is optional
metadata, not a condition for syntax analysis. A `BumperProject` can contain
`Included` and `Rules` without an `Architecture` block.

Scoped repository closures receive `{ subjects, context in ... }`. Subjects are
selected files. The full context supports cross-file lookups. A diagnostic
outside the selected subjects fails evaluation explicitly.

Match rules evaluate typed SwiftSyntax nodes and retain their file context:

```swift
// .bumper/Sources/ProjectRules.swift
import BumperBowlingCore
import SwiftSyntax

let projectRules = RuleSet {
    Rules.each(
        SyntaxQuery<TupleTypeSyntax>(),
        id: "core.no_tuple_api",
        severity: .error,
        summary: "Core code uses named types instead of tuples.",
        scope: .under("Sources/Core")
    ) { tuple in
        [tuple.failure(message: "Tuple type must use a named type.")]
    }
}
```

Raw syntax assertions use SwiftSyntax's own `SyntaxKind` values:

```swift
Requires(RequireSyntax(.enumDecl), severity: .error)
Requires(DisallowSyntax(.forceUnwrapExpr), severity: .warning)
```

Bumper Bowling does not maintain a parallel enum of SwiftSyntax nodes. Facts that need typed access to syntax fields are computed from real SwiftSyntax node types through `node.bumper` views.

```text
BumperProject -> ArchitectureConfiguration -> scanner -> RepositoryInput -> project runner -> RepositorySyntax -> facts -> RuleSet -> RuleReport (+ EvaluationTelemetry)
```

## Design Goals

- Feel familiar beside SwiftLint without overlapping SwiftLint's style lane.
- Keep the tool tiny.
- Prefer positive architecture vocabulary over free-floating negative rules.
- Make every violation explainable as observed fact plus declared lane.
- Support agentic coding loops by making architecture executable in hooks, CI, and tests.
- Parse strings into typed values at the boundary.
- Avoid generated accessors, dynamic lookup, JSON config, plugins, and clever configuration machinery.
- Keep parsing SwiftSyntax-first and Swift-only.
- Do not duplicate SwiftSyntax's syntax model. Extend and compose over SwiftSyntax types instead.

## Default File Shape

```swift
import BumperBowlingCore

enum AppComponent: String, ComponentKey {
    case core
    case cli
}

let bumper = BumperProject {
    Included {
        "Sources"
    }

    Excluded {
        ".build"
        "DerivedData"
    }

    Architecture(AppComponent.self) {
        Component(.core) {
            Owns("Sources/BumperBowlingCore")
            Modules("BumperBowlingCore")
            MayUse(.foundation)
            Requires(
                .explicitDomainSurfaces,
                .typedIdentity,
                .immutableStoredState,
                severity: .warning
            )
        }

        Component(.cli) {
            Owns("Sources/BumperBowling")
            Modules("BumperBowling")
            MayDependOn(.core)
            MayUse(.foundation)
        }
    }

    Rules {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        SourceCoverage(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

`Architecture(AppComponent.self)` takes the project's own `ComponentKey` enum,
so `Component(.core)` and `MayDependOn(.core)` are compiler-checked. Duplicate
component IDs after normalization are a configuration error. The untyped
`Architecture { Component(.core) { ... } }` spelling over `ComponentID` values
remains valid.

## Core Vocabulary

- `Component`: a named architectural area.
- `Owns`: paths owned by that component.
- `Modules`: module aliases that identify that component in imports.
- `MayDependOn`: an allowed optional dependency edge.
- `DoesNotDependOn`: a forbidden dependency edge.
- `MayUse`: allowed capability imports for a component.
- `DoesNotUse`: component-scoped modules or frameworks that must not appear in imports.
- `Declare`: a public declaration predicate over parsed declaration facts.
- `Declares`: sugar for `Does(Declare(...))`.
- `ContainSyntax`: a SwiftSyntax node-kind predicate over parsed syntax nodes.
- `ContainSyntaxNode`: a generic predicate over observed SwiftSyntax node
  family, node kind, and spelling.
- `Does`: asserts that a predicate is present in the component graph.
- `DoesNot`: asserts that a predicate is absent from the component graph.
- `StringMatcher`: typed matching for name-like facts; string literals are exact matches, with `.contains`, `.prefix`, `.suffix`, and `.regex` available explicitly. Regex patterns validate at construction.
- `Requires`: positive modeling guarantees that derive syntax-first checks.
- `ComponentShape`: reusable component policy bundle owned by the consumer.
- `AssertionShape`: reusable repo-level assertion bundle owned by the consumer.
- `ApplyAssertions`: applies an `AssertionShape` inside `Rules`.
- `Disallows`: concrete syntax nodes that must not appear in a component.
- `NoDirectStringMatching`: a syntax-first assertion that keeps direct string matching inside the matcher implementation.
- `Rules`: the project rule block — graph-level assertions such as ownership and dependency shape, plus project-defined `RuleDefinition` values. `Rules.*` static members are the prebuilt shaper catalog.

Current modeling requirements include:

- `.explicitDomainSurfaces`: shorthand for no `Any` or broad existential stored properties.
- `.typedIdentity`: shorthand for no raw `String` stored properties.
- `.computedState`: shorthand for no stored properties in the configured scope.
- `.functionalCore`: shorthand for no selected imperative syntax constructs.
- `.noStoredProperties`: disallow any stored property.
- `.noAnyStoredProperties`: disallow stored properties explicitly typed as `Any`.
- `.noBroadExistentialStoredProperties`: disallow stored properties with explicit `any ...` types.
- `.noBoolStoredProperties`: disallow stored properties explicitly typed as `Bool`.
- `.noOptionalStoredProperties`: disallow stored properties explicitly typed as optional.
- `.noRawStringStoredProperties`: disallow stored properties explicitly typed as `String`.
- `.immutableStoredState`: disallow mutable stored properties where configured.
- `.enumStateMachine`: require parser/workflow files to declare an enum state machine where configured.

Concrete imperative facts can be disallowed directly:

```swift
Disallows(.assignment, .loop, .mutableBinding)
```

## Commands

```bash
bumper init [root]
bumper lint [root]
bumper test [root]
bumper scan [root]
bumper snapshot [root]
bumper config [root]
bumper explain <path>
```

## Rules

- `forbidden_import`
- `component_boundary`
- `duplicate_ownership`
- `declared_dependency_cycle`
- `stored_properties`
- `syntax_constructs`
- `enum_state_machine`
- `syntax_kinds`
- `public_declarations`

Direct string matching is conservative. SwiftSyntax can show an operator token or a member-call spelling, but it does not type-check the operands. Bumper Bowling flags obvious string-like comparisons and string matching calls; a compiler-backed analyzer would be needed for perfect `String` certainty.

Severities are:

```swift
off
note
warning
error
```

Only `error` fails `bumper lint`.

`stored_properties` is syntax-first. It checks explicit stored-property type annotations exactly enough to catch mutable stored properties, `Any`, `any ...`, and raw `String` in configured paths. It does not claim compiler-level type inference or full signature analysis.

See [RULE_AUTHORING.md](RULE_AUTHORING.md) for guidance on composing
repository-owned requirements, component shapes, assertion shapes, and examples.

## SwiftSyntax Boundary

Bumper Bowling is SwiftSyntax-driven:

```text
SwiftSyntax -> RepositorySyntax -> typed facts -> ArchitectureGraph -> RuleSet
```

Swift is the only language surface. The configuration language must not promise facts SwiftSyntax cannot observe, such as symbol resolution, inferred types, or compiler-level dependency truth.

See [SWIFTSYNTAX_SURFACE.md](SWIFTSYNTAX_SURFACE.md) for the current fact surface.

## Testing Pattern

Bumper Bowling follows a tiny version of SwiftLint's self-test pattern:

- Rule fixtures use `↓` markers for expected violation locations.
- Every rule can be tested in memory with `RuleTestHarness` from
  `BumperBowlingTestSupport`. Pass an array of `SourceInput` values to receive
  the same `RuleReport` the engine and CLI produce.
- Command tests cover `scan` and `lint`.
- A self-lint test runs Bumper Bowling against this repository and records error-level findings.

## Source coverage

Add `SourceCoverage(.error)` to `Rules` to require exactly one component owner for each included Swift file.
`SingleOwner` continues to check overlapping configured paths, including paths without files.

The scanner inventories included source files before it resolves owners. Exclusions apply before inventory.
Unowned Swift files produce findings with their paths and an instruction to add ownership or exclude the files.
Unowned Swift files enter syntax analysis. Component scopes select only owned files.
Ownership paths that match no included source files produce warnings, capped at the configured severity.
Paths with only unsupported source languages produce notes, so an intentional Objective-C shim does not fail the coverage assertion.

Both scan and lint JSON include a `coverage` object:

- `includedFileCount`: included source files, including recognized unsupported languages.
- `scannedFileCount`: all included Swift files passed to syntax analysis, including unowned files.
- `unownedFileCount` and `unownedPaths`: included Swift files without owners.
- `overlappingPaths`: included Swift files with multiple component owners.
- `languages`: counts by file extension, with an explicit `isSupported` flag.
- `scopes`: supported and unsupported file counts for each configured component path.

The inventory recognizes `.swift`, `.m`, `.mm`, `.h`, `.c`, `.cc`, `.cpp`, `.cxx`, and `.hpp` files.
Unsupported-language symlinks count in the inventory. The scanner does not read or resolve their targets.
Swift-source symlinks remain rejected.
Only `.swift` files receive syntax analysis. These counts do not establish build-target membership or compiler-verified language identity.
The source-count limit includes unsupported source files. Swift byte limits include unowned Swift files.

For programmatic rule evaluation, use `RepositoryScanner.scanInput(root:)` to obtain a `RepositoryInput` with coverage metadata.
The metadata survives JSON serialization to the project runner.
`scanSources(root:)` now throws for an unowned Swift file instead of returning a silently incomplete array.
`scan(root:)` retains coverage in `RepositoryFacts`.
Coverage evaluation fails explicitly when its input has no inventory.
Existing configurations keep coverage disabled until they add the assertion. Newly generated configurations include it.
