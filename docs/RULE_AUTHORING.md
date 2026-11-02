# Author a repository convention

Start with a repeated review comment and a clear repair. State which declarations
it concerns, where it applies, and what must hold. Build that policy in Swift.

Bumper supplies queries, builders, and source locations. SwiftLintFramework owns
execution, cached parsing, collection, disable directives, and reporting.

## Build the rule

A `SyntaxRule` declares static `metadata` and a static `body: SyntaxCheck`.
The body is a builder. The [starter](../Sources/BumperBowlingCore/Starter/Sources/BumperRules/SwiftUIPreviewRule.swift)
selects each feature view with `Rules.forEach` and requires a matching preview.

Use these operations:

- `Rules.forEach(query, scope:)` builds checks for each typed match.
- `Rules.require(condition, at:message:)` reports an unmet condition at a match.
- `Rules.require(inSameFile:at:message:)` requires a companion from the same syntax tree.
- `Rules.forbid(query, scope:)` rejects each matching occurrence.
- `Rules.each` and `Rules.files` accept ordinary callbacks returning `[RuleFailure]`.

A requirement's `at:` argument sets its diagnostic location. It does not select
subjects or hide findings outside the rule scope.

Sibling checks all execute. They can support several aspects of one convention.
Keep unrelated conventions in separate rule types with separate identifiers.

Use local constants, conditions, optional bindings, switches, and loops inside
the builder. Use ordinary Swift helpers for algorithms that need `guard`, early
return, or throwing control flow. A helper can return one `SyntaxCheck`; give it
`@CheckBuilder` if it composes several checks.

The [direct-member example](../.bumper/Sources/BumperRules/ExplicitCodingKeysRule.swift)
uses an optional binding, sets, and nested loops. It checks explicit CodingKeys
coverage while allowing compiler synthesis when no keys are declared.

Public rule types need public metadata and bodies. They do not need native
configuration storage or an initializer. Bumper supplies a distinct SwiftLint
adapter for each type.

## Query the existing tree

`SyntaxQuery<Node>` accepts any SwiftSyntax node type. It returns typed matches
with `node` and `file`. `file.syntax` is SwiftLint's cached tree. Never reparse it.

Common query roots include `structs()`, `functions()`, `initializers()`,
`variables()`, `typeAliases()`, `functionCalls()`, and `macroExpansions()`.
Use `imports(["Network"])` for written root-module imports. Boundary checks can
use `Rules.importOwnership`, `Rules.forbiddenImports`, or `Rules.sourceOwnership`
inside their named rule body. See the [boundary migration guide](BOUNDARY_MIGRATION.md)
for declaration access, contract types, alias limits, and complete recipes.
Use a generic query for everything else:

```swift
SyntaxQuery<EnumDeclSyntax>().filter { $0.name == "AppRoute" }
```

Queries compose with `filter`, `compactMap`, `containing`, `without(inSameFile:)`,
`within`, and `excluding`. A custom `SyntaxPattern` can supply its own matches.

`matches(within:)` selects strict descendants. `members(of:)` selects direct
members and excludes declarations in nested types. Same-file requirements check
both the file tree and the matched node's tree, including custom query results.

Use `variable.isMutable`, `variable.bindingNames`, and
`variable.storedBindingNames` for common binding questions.
`variables().storedMembers()` excludes globals, locals, and computed properties.
Property observers count as stored bindings.

For custom logic, inspect `match.node` or walk `file.syntax` with a
`SyntaxVisitor`. Return `match.failure(message:)` or
`file.failure(at:message:)` to retain the source location. The context also
provides the repository-relative `path`, canonical repository `root`, original
`source`, and location converter.

## Select subjects separately from collection

Scopes use repository-relative paths:

```swift
.under("Sources/Features")
.files(["Sources/App/Routes.swift"])
RuleScope.repository.excluding(.under("Sources/Generated"))
.under("Sources/Transport").union(.files(["Sources/TLS.swift"]))
```

A custom scope can inspect `SourceFileContext`. `.under` matches path components,
so `Sources/FeatureTests` does not fall under `Sources/Features`.

Put subject scope on the outer selection. Paths in that check structure are
validated before execution even when nothing matches. A per-match callback does
not run, or contribute scope declarations, for an absent match.

A `RepositoryRule` declares typed `FileInfo` and a static
`body: RepositoryCheck<FileInfo>`. Its `Rules.repository` collection closure is
ordinary Swift. Its validation closure is a check builder, so it can loop over
collected subjects and emit requirements.

Collection includes every scanned file. Scope selects the files to check and
the locations the rule can report. SwiftLint completes collection before
validation. Evidence from another directory can satisfy a scoped subject.

A repository rule with no selected subject fails before validation. A DSL
finding outside the rule's subject scope also fails. Neither becomes a passing
lint result. Composed file checks bound that rule scope by their union.

See the [route example](../.bumper/Sources/BumperRules/RouteRegistrationsRule.swift).
It uses ordinary counts to require exactly one registration for each route.
There is no shared fact engine.

## Register and share rules

```swift
BumperProject(included: ["Sources"], excluded: ["Sources/Generated"]) {
    SwiftUIPreviewRule.self
    ExplicitCodingKeysRule.self
    RouteRegistrationsRule.self
}.main()
```

The project builder supports conditions, loops, and native SwiftLint rule types.
Duplicate identifiers fail. One rule type has one stable identifier. Bumper does
not synthesize runtime types for closure instances with different IDs.

To share conventions, export public rule types from a named Swift package.
Add that library as a dependency of another repository's runner and tests.
Register only the selected types. Use a distinct module name if that repository
also has local rules. Typed instance options are not part of this API.

## Preserve the meaning with examples

Use `RuleTestHarness(MyRule.self)` from `BumperBowlingTestSupport`. A harness can
also use the project builder syntax to register several authored or native rules:

```swift
let harness = RuleTestHarness {
    SwiftUIPreviewRule.self
    ExplicitCodingKeysRule.self
}
```

Evaluate passing and failing arrays of `.swift(path, source:)` fixtures through
the same harness. Assert zero findings for passing examples. For failing examples,
assert the count and use `ViolationMatcher` for identity, path, location, severity,
and reason. Include near misses that could satisfy the wrong relationship.

The harness writes fixtures under an isolated temporary root and uses SwiftLint's
execution path. It normalizes findings and removes temporary files. It does not
change the process directory or introduce another evaluator.

Run these tests with `bumper test .`, or `swift test --package-path .bumper`.

## Limits

These are syntax checks. Written conformances can differ from compiler type
identity. A call's spelling does not establish its resolved declaration.
Aliases, indirect calls, extensions, and synthesized declarations need explicit
policy decisions. Do not describe these checks as compiler-backed analysis.

Rule bodies and callbacks are nonthrowing, matching SwiftLint's rule API.
Configuration and input preflight failures stop the host. Do not catch an
analysis error and return an empty finding list. Native `SourceKitFreeRule`
remains available when the DSL does not improve a rule.
