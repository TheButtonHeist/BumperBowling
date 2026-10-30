# Rule Authoring

Bumper Bowling does not ship a house architecture. It ships one open rule
engine, SwiftSyntax-observed facts, and typed composition points so each
repository can define its own architecture vocabulary.

Custom rules can inspect the full SwiftSyntax tree. `SyntaxQuery<Node>` accepts
any SwiftSyntax node type. Queries, ordinary Swift closures, and shared facts
can express requirements inside declarations and relationships across files.

The [executable rule recipes](RULE_RECIPES.md) demonstrate these forms through
the public test harness.

Architecture is optional. The scanner supplies all included Swift sources,
including unowned files. Source descriptors and derived source facts use an
optional `component`. Component dependency facts contain only owned sources.
`SourceCoverage` can report missing or overlapping ownership separately.

Every rule — built-in or project-defined — is a `RuleDefinition` evaluated over
one immutable `RuleContext`, producing `RuleFailure` values that become
`RuleViolation`s in one `RuleReport`. There is no second engine, no registry,
and no separate diagnostic shape for project rules.

## The Ladder

Author a rule at the highest level that expresses it, and move down only when
the level above cannot:

1. **Architecture DSL** — components, ownership, dependencies, capabilities,
   and `Requires(...)` bundles inside `Architecture { ... }`. Most policy
   belongs here.
2. **Standard shapers** — prebuilt `Rules.*` factories for common ownership and
   traversal invariants. One call, typed arguments.
3. **Closure rules over typed facts** — `Rules.repository(...)` with memoized
   `FactProvider` values when the invariant is repo-specific but the facts are
   standard.
4. **Syntax rules and typed queries** — `Rules.each(...)` for each typed match,
   `Rules.files(...)` for each file, and `SyntaxQuery` for parsed syntax.
5. **Raw `SyntaxVisitor`** — `VisitorRule` when nothing above fits. This is a
   permanent escape hatch, not a deprecation lane.

Before admitting a rule, state the observed fact, scope, and mismatch. Reject
rules for historical spellings, malformed Swift, and states the compiler
already makes unconstructible. For a rule below the standard-shaper rung,
explain why the next higher rung cannot express the invariant and audit an
existing rule at that rung or lower for deletion or promotion.

Every project rule has two explanations:

- Its explicit `summary` is the concise runtime explanation attached to a
  violation. Do not rely on a generic factory default.
- The consumer's rule catalog records rationale, scope, repair, proof, and the
  condition that will let the project delete the rule.

When one visitor shares a parse pass across several checks, catalog every
sub-invariant. One umbrella rule ID must not hide undocumented policy.

## Terms

- `RuleDefinition`: one rule — identity (`RuleMetadata`), scope (`RuleScope`),
  and an `evaluate(in:)` over `RuleContext`.
- `RuleContext`: the immutable evaluation context: configuration, the
  parse-once `RepositorySyntax`, and the memoized fact cache.
- `RuleFailure`: one finding from a rule; rule metadata is attached by the
  engine to produce a `RuleViolation`.
- `RuleSet`: an ordered collection of rules built with a result builder.
- `FactProvider`: a typed, memoized derivation over the parsed repository.
- `RuleScope`: where a rule applies — `.repository`, `.under(path)`,
  `.component(id)`, `.files(paths)`, or any predicate.
- `ComponentShape` / `AssertionShape`: reusable bundles of component and
  repository policy for the architecture DSL.

## Composition

Bumper Bowling does not define a house architecture. A repository composes its
own vocabulary from typed values.

`ComponentRequirement` groups source-fact requirements. `ComponentShape`
groups component elements. `AssertionShape` groups repository-level rule
configuration.

`Applies(...)` inserts a shape into the current component. The component's
owned paths set the default scope for its requirements. A shape can include
another shape. Importing a source file or a local rule package does not apply a
shape.

Define a `RuleDefinition` with a `RuleScope` when composition cannot express a
check. That rule uses the same engine and report format as a built-in rule.

## Standard Shaper Catalog

All shapers are static members of `Rules`, implemented only through the public
rule, fact, and query interfaces. Each accepts an optional `id:` and
`severity:`.

| Shaper | Asserts |
| --- | --- |
| `Rules.importOwnership(_:allowed:)` | Matching module imports occur only inside the allowed scope. |
| `Rules.memberReferenceOwnership(_:allowed:)` | Matching member-access spellings occur only inside the allowed scope; this is syntax, not property or method resolution. |
| `Rules.singleDeclaration(_:owner:)` | Exactly one declaration of the symbol, under the owner path. A configured owner with no files is a configuration error. |
| `Rules.constructionOwnership(_:allowed:)` | The type is constructed only inside the allowed scope. |
| `Rules.canonicalConstruction(_:owners:)` | Same check, spelled for canonical-value ownership. |
| `Rules.boundaryOnly(function:allowed:)` | Calls to the function occur only inside the boundary scope. |
| `Rules.noAlternateAliases(_:allowing:)` | No `typealias` re-exposes the symbol outside the allowing scope. |
| `Rules.canonicalTraversal(root:structuralCase:owners:)` | Recursive traversal of the type — direct or mutual, over locally dispatched calls — stays with its owners. |
| `Rules.singleNominalSpelling(suffix:owner:)` | Every nominal declaration named with the suffix lives in the owner scope, using typed declaration facts. |

Symbols and paths are `ExpressibleByStringLiteral`, so authoring stays plain:

```swift
Rules.singleDeclaration("AccessibilityTarget", owner: "Sources/Plans")

Rules.canonicalTraversal(
    root: "AccessibilityHierarchy",
    structuralCase: "container",
    owners: .under("Sources/Traversal")
)
```

Read [Build An Architecture Rule From The Ground Up](RULE_FROM_THE_GROUND_UP.md)
for a walkthrough of this rule's syntax, facts, composition, and use.

## Closure Rules Over Typed Facts

`Rules.repository(_:severity:summary:_:)` evaluates once over the whole repository.
Request facts through `context.facts(_:)`; providers are derived once per run
and memoized:

```swift
Rules.repository(
    "project.no_uikit",
    severity: .error,
    summary: "UIKit imports stay at the application boundary."
) { context in
    try context.facts(BuiltInFacts.imports).occurrences
        .filter { $0.module.rawValue == "UIKit" }
        .map { RuleFailure(path: $0.path, message: "UIKit is not allowed here.") }
}
```

Built-in providers under `BuiltInFacts`:

| Provider | Fact |
| --- | --- |
| `sourceFiles` | Projected per-file facts (imports, declarations, stored properties, constructs). |
| `imports` | Every import occurrence with module, path, and component. |
| `declarations` | Nominal declaration inventory with `occurrences(of:)` lookup. |
| `nominalTypes` | Typed nominal declarations with kind, access, inheritance, and location. |
| `extensions` | Extension declarations. |
| `storedProperties` | Stored properties with explicit types and mutability. |
| `syntaxNodes` | The observed syntax-node catalog. |
| `functionCalls` | Function and initializer calls with `calls(to:)` lookup. |
| `directRecursion` | Functions that call themselves. |
| `recursiveCallGroups` | Strongly connected components of the locally dispatched call graph — direct and mutual recursion; calls on another receiver never form edges. |
| `effectiveAccess` | Legacy nominal-only access caps. |
| `declarationContracts` | Explicit signature types, enclosing context, and lexical access with unresolved results. |
| `enclosingDeclarations` | Each declaration's enclosing nominal chain. |
| `memberReferences` | Member accesses with optional base names. |
| `componentDependencies` | Component-to-component import edges. |

With `scope:`, a repository closure takes `{ subjects, context in ... }`.
Subjects are the selected source files. Context and shared facts still cover
the full input. Diagnostics must anchor selected subjects. An outside diagnostic
is an explicit evaluation error. The [factory reference](built-ins/rule-factories.md#repository-rule)
defines empty scopes and diagnostic anchors.

### Defining Your Own Fact Provider

A provider is a value type with a stable `id` and a `derive(in:)`:

```swift
struct DeclarationsPerFile: FactProvider {
    let id: FactProviderID = "project.declarations_per_file"

    func derive(in context: FactDerivationContext) throws -> [RelativeFilePath: Int] {
        let occurrences = try context.facts(BuiltInFacts.declarations).occurrences
        return Dictionary(grouping: occurrences, by: \.path).mapValues(\.count)
    }
}
```

Providers may request other providers through `context.facts(_:)`; cycles are
explicit errors, never deadlocks or empty results. Derivation failures fail the
run — an analysis error is never an empty match set.

A provider ID identifies its complete derivation, including parameters. Two
providers with the same ID share the first result or error within one run.
Different parameter values need different IDs if they produce different facts.
The cache does not compare provider values or inspect closure captures.

## Per-File Syntax Rules and Typed Queries

`Rules.files(_:severity:summary:_:)` runs once per parsed file. The whole run parses
each file exactly once; every rule shares the same trees.

Typed queries compose over the parsed file and preserve node types:

```swift
Rules.each(
    typeAliases().aliasing("AccessibilityTarget"),
    id: "project.no_alternate_aliases",
    summary: "AccessibilityTarget has one spelling."
) { match in
    [match.failure(message: "\(match.node.name.text) aliases AccessibilityTarget.")]
}
```

Query roots: `functions()`, `initializers()`, `variables()`, `typeAliases()`,
`structs()`, `macroExpansions()`, `nominalDeclarations()`, `functionCalls()`.
Queries filter files with
`within(_:)` and filter nodes with `lexically(within:)` or
`lexically(excluding:)`. `SyntaxScope`
composes file, type-member, local, protocol, enclosing-type, and
enclosing-function predicates without coupling them to repository paths.

Common match facts use direct access: `match.lexicalContext`,
`variable.isMutableBinding`, and `variable.bindingNames`. For stored member
declarations, use `variables().storedMembers()`. Query predicates can use
key paths, such as `.filter(\.isMutableBinding)`.

These conveniences reuse the existing syntax facts. `match.node` retains full
SwiftSyntax access. The [query reference](built-ins/syntax-queries.md#match-context-and-facts)
defines the selection rules and includes a complete example.

Typed syntax views expose value-only `LexicalContext` and `TypeShape` facts.
Type shapes describe explicit binding and typealias syntax, including
referenced type names, the outer type spelling, function-type shape, and
attributes. TypeShape itself does not resolve aliases.
`LexicalTypeResolver(file:)` adds bounded, same-file alias lookup and lexical
global-actor attribute facts. See [declaration contracts and lexical lookup](built-ins/facts.md#declaration-contracts-and-lexical-lookup)
for the supported wrappers and explicit unresolved results. Compiler type
identity and cross-file resolution remain outside this syntax layer.

Capability-specific operations such as `taking(_:)`, `callingSelf()`,
`aliasing(_:)`, `inheriting(_:)`, and `excluding(_:)` narrow matches while keeping the concrete
SwiftSyntax node type, so `match.node` needs no casting.

### Raw Visitor Escape Hatch

When nothing typed fits, walk the tree yourself:

```swift
import SwiftSyntax

final class ForceUnwrapVisitor: SyntaxVisitor, RuleFailureSource {
    private let file: SourceFileContext
    private(set) var failures: [RuleFailure] = []

    init(file: SourceFileContext) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        failures.append(file.failure(at: node, message: "Force unwrapping is not allowed here."))
        return .skipChildren
    }
}

Rules.visitor(
    "project.no_force_unwrap",
    severity: .error,
    scope: .under("Sources"),
    summary: "Production code handles optional absence explicitly."
) { file in
    ForceUnwrapVisitor(file: file)
}
```

`SourceFileContext` exposes `path`, `component`, `source`, `syntax`,
`position(of:)`, `location(for:)`, and `failure(at:message:evidence:)`.

## Wiring Rules Into The Project

Project rules join built-ins in the `Rules` block of `BumperBowling.swift`:

```swift
let bumper = BumperProject {
    Architecture(AppComponent.self) {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
        }
    }

    Rules {
        DependencyBoundaries(.error)
        Rules.singleDeclaration("AccessibilityTarget", owner: "Sources/Core")
        projectRules
    }
}
```

Rule IDs must be unique across built-in and project rules; a duplicate is a
configuration error. Rules evaluate sequentially in declaration order, and the
final report is sorted by path, line, column, rule ID, then message — so
declaration order never changes the report.

Add or update the consumer's rule-catalog entry in the same change that wires
the rule into the project.

## Where To Define Vocabulary

Use the smallest placement that keeps the configuration readable.

### Inline

For one-off vocabulary, define values directly in `BumperBowling.swift`.

### Repo-Local `.bumper/Sources`

For vocabulary that belongs to one repository, put Swift files under
`.bumper/Sources`. Bumper Bowling compiles those files beside
`BumperBowling.swift` in the project runner:

```text
.bumper/
  Sources/
    ArchitectureVocabulary.swift
    ProjectRules.swift
BumperBowling.swift
```

```swift
// .bumper/Sources/ArchitectureVocabulary.swift
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
```

Repo-local `.bumper/Sources` files can import `SwiftSyntax` directly.

### Local SwiftPM Package

For vocabulary shared by multiple repositories, use a normal SwiftPM package at
`.bumper/Package.swift`. Bumper Bowling expects a `BumperRules` library product
and makes it importable from `BumperBowling.swift`. Importing a package never
applies rules by convention; the project still opts in explicitly inside
`Rules { ... }`. A packaged rule library must declare its own SwiftSyntax
dependency when it names AST types.

## Testing Rules

Every project-defined closure, query, or visitor rule needs a positive fixture
and a minimal mutation fixture. Assert the exact rule ID, path, message,
available location, and promised evidence. Standard shapers are tested by
Bumper Bowling; consumers test their own configuration and project rationale.

Put repository-owned rule tests under `.bumper/Tests` and run them from the
repository root:

```text
.bumper/
  Sources/ProjectRules.swift
  Tests/ProjectRulesTests.swift
```

```bash
bumper test
```

`bumper test [root]` compiles `BumperBowling.swift`, repo-local rule sources,
and the test files into one cached SwiftPM test target in source mode. When
`.bumper` is a Swift package, Bumper runs ordinary `swift test` with
`--package-path .bumper` instead, so the package owns its test targets and
`@testable` imports have normal package-test visibility. Swift Testing and
XCTest discovery work normally, and their exit status is returned by `bumper`.
These tests are ordinary trusted project code and run with the same access as
`swift test`; the configuration evaluation sandbox is not a test sandbox.

`BumperBowlingTestSupport` tests exactly one rule (or one `RuleSet`) in memory,
with no checkout and no filesystem, returning the same `RuleReport` the engine
and CLI produce:

```swift
import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Test
func flagsForeignDeclarations() throws {
    let rule = Rules.singleDeclaration("AccessibilityTarget", owner: "Sources/Plans")

    let report = try RuleTestHarness(rule).evaluate(
        VirtualRepository {
            VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
            VirtualSourceFile.swift("Sources/Score/Foreign.swift", component: "score", source: "struct AccessibilityTarget {}")
        }
    )

    #expect(report.violations.map(\.path.rawValue) == ["Sources/Score/Foreign.swift"])
}
```

`VirtualSourceFile.swift(_:component:source:)` accepts strings, `ComponentID`,
or your project's `ComponentKey` enum. The harness is framework-neutral — it
works under Swift Testing and XCTest alike.

## Profiling Rules

Every evaluation measures itself. `bumper lint --timings` prints the host
phases (prepare, scan, evaluate) plus the slowest rules and fact providers to
stderr, so a slow project rule is attributable by ID. Programmatically, the
same numbers come from `evaluationRun`:

```swift
let run = try ruleSet.evaluationRun(configuration: configuration, repository: repository)
run.telemetry.ruleSeconds.first  // the slowest rule, by ID
run.telemetry.factSeconds        // per-provider derivation cost, slowest first
```

Fact durations are inclusive: a provider that derives other facts is charged
for its dependencies. Providers derive at most once per run, so a fact
appearing here cost exactly what it shows.

Evaluation runs under a bounded budget (60 seconds by default). Raise it for
legitimately large repositories with `BUMPER_EVALUATION_TIMEOUT_SECONDS`;
profile with `--timings` before reaching for a bigger budget.

## Built-In DSL Primitives

Read the [built-in rule authoring catalog](built-ins/README.md) for every
component requirement, graph assertion, shaper, query, scope, and fact
provider. The catalog maps each convenience to its lower-level pieces.

### Scoped syntax cardinality

For syntax policies that are about how often a pattern occurs per file, use
`Rules.assert`. It scopes the rule, evaluates a public `SyntaxPattern`, and
reports the observed count as structured evidence. Excess matches retain their
source location; missing matches report against the affected file.

The default counting unit is `.perFile`. Use `counting: .repository` to combine
matches across selected files. File scope and counting unit are independent.
The [factory reference](built-ins/rule-factories.md#cardinality-rule) defines
shortage diagnostics, empty scopes, and count validation.

```swift
Rules.assert(
    functionCalls(),
    cardinality: .none,
    id: "domain.no_function_calls",
    summary: "Domain files do not make function calls.",
    scope: .under("Sources/Domain")
)

Rules.assert(
    SyntaxQuery<EnumDeclSyntax>(),
    cardinality: .atLeast(1),
    id: "workflow.has_enum",
    summary: "Each workflow file declares an enum."
)
```

Available cardinalities are `.none`, `.atLeast(_)`, `.atMost(_)`, and
`.exactly(_)`. This API is neutral over SwiftSyntax node types; domain-specific
defaults should compose it rather than add privileged rule infrastructure.

## Boundary

Use SwiftLint for local style, formatting, and code-smell policy.

Use the Swift compiler for inferred types, symbol resolution, macro expansion,
protocol conformance truth, and build-target truth.

Use Bumper Bowling when the rule is about project policy and SwiftSyntax
can observe enough source facts to report deterministic evidence.

Every finding should be explainable as:

```text
observed source fact + declared scope = mismatch
```

If Bumper Bowling cannot show the observed fact, it should not report the
violation.

## Authoring Guidance

- Prefer positive vocabulary: `Requires(.domainCore)` is easier to review than
  scattered prohibitions.
- Author at the highest rung of the ladder that expresses the rule.
- Keep vocabulary repository-owned unless several repositories actually share
  it.
- Start narrow. Scope stricter requirements to paths that are already clean or
  intentionally being cleaned.
- Use warning severity for migration lanes and error severity for contracts CI
  should enforce.
- Do not encode SwiftLint rules as Bumper rules.
- Do not encode compiler questions as SwiftSyntax rules.
- Do not add generated accessors, registries, remote package policy, JSON
  configuration, or auto-loaded rules.
