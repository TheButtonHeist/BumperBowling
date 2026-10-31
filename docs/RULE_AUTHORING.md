# Author a repository convention

Start with a repeated review comment and a clear repair. Describe the passing
and failing examples before writing the predicate.

Bumper is a Swift DSL over SwiftLintFramework and SwiftSyntax. Each authored
rule becomes a distinct native SwiftLint rule. No umbrella rule hides other
rules or calls the old Bumper evaluator.

## Choose the shape

- Use `SyntaxRule` and `Rules.forbid` to reject selected syntax matches.
- Use `Rules.each` when each selected declaration needs its own check.
- Use `Rules.files` for arbitrary SwiftSyntax or visitor logic in one file.
- Use `RepositoryRule` and `Rules.repository` for relationships across files.

Each rule declares `metadata`, a `configuration = RuleSettings<Self>()`, and a
`body`. `RuleSettings` carries the repository root through SwiftLint’s native
configuration. The rule’s reviewed Swift source defines policy and severity.

The [starter](../Sources/BumperBowlingCore/Starter/Sources/BumperRules/SwiftUIPreviewRule.swift)
shows a complete same-file rule. Exported rule types need public members and
`public init()` so another Swift package can register them.

## Query the existing tree

`SyntaxQuery<Node>` accepts any SwiftSyntax node type. It returns typed matches
with `node` and `file`. `file.syntax` is SwiftLint’s cached tree. Never reparse it.

Common query roots include `structs()`, `functions()`, `initializers()`,
`variables()`, `typeAliases()`, `functionCalls()`, and `macroExpansions()`.
Use a generic query for everything else:

```swift
SyntaxQuery<EnumDeclSyntax>().filter { $0.name == "AppRoute" }
```

Queries compose with `filter`, `compactMap`, `containing`, `without(inSameFile:)`,
`within`, and `excluding`. A custom `SyntaxPattern` can supply its own matches.

`matches(within:)` selects strict descendants. `members(of:)` selects direct
members and excludes declarations in nested types. Matches keep source identity,
so an unrelated file cannot satisfy a same-file relationship.

Use `variable.isMutable`, `variable.bindingNames`, and
`variable.storedBindingNames` for common binding questions.
`variables().storedMembers()` excludes globals, locals, and computed properties.
Property observers count as stored bindings.

For custom logic, inspect `match.node` or walk `file.syntax` with a
`SyntaxVisitor`. Return `match.failure(message:)` or
`file.failure(at:message:)` to retain the source location.

## Select subjects separately from collection

Scopes use repository-relative paths:

```swift
.under("Sources/Features")
.files(["Sources/App/Routes.swift"])
RuleScope.repository.excluding(.under("Sources/Generated"))
```

A custom scope can inspect `SourceFileContext`. `.under` matches path components,
so `Sources/FeatureTests` does not fall under `Sources/Features`.

A repository rule collects typed `FileInfo` from every included file. Its
scope selects the files to check and the locations it can report. SwiftLint
stores that collection and completes collection before validation.

A repository rule with no selected subject fails before validation. A DSL
finding anchored outside the subject scope also fails. Neither condition becomes
a passing lint result.

See the [route example](../.bumper/Sources/BumperRules/RouteRegistrationsRule.swift).
It keeps collection and subject selection explicit without a shared fact engine.

## Test the real rule

Use `RuleTestHarness(MyRule.self)` from `BumperBowlingTestSupport`. Evaluate paired
passing and failing arrays of `.swift(path, source:)` fixtures. Keep one harness
for the pair.

For passing examples, assert zero findings. For failing examples, assert the
count and use `ViolationMatcher` to assert the ID, path, line, column, severity,
and reason. Test near misses that could satisfy the wrong relationship.

The harness writes fixtures under an isolated temporary root and uses the same
SwiftLint execution path as the repository runner. It normalizes diagnostic
paths and removes the temporary files. It does not change the process directory.

Run these tests with `bumper test .`, or use ordinary `swift test --package-path .bumper`.

## Register and share rules

```swift
BumperProject(included: ["Sources"], excluded: ["Sources/Generated"]) {
    SwiftUIPreviewRule.self
    ExplicitCodingKeysRule.self
    RouteRegistrationsRule.self
}.main()
```

The builder supports conditions, loops, and distinct native SwiftLint rule types.
Duplicate identifiers fail. One rule type has one stable identifier. Bumper does
not synthesize runtime types for closure instances with different IDs.

For distribution, export rule types from a named Swift package. Add that library
as a dependency of another repository’s runner and tests. Register the selected
types there. Use a distinct module name if that repository also has local rules.

## Limits

These are syntax checks. A written conformance can differ from compiler type
identity. Matching a call’s spelling cannot establish its resolved declaration.
Aliases, indirect calls, extensions, and synthesized declarations need explicit
policy decisions. Do not describe these checks as compiler-backed analysis.

Rule predicates are nonthrowing, matching SwiftLint’s rule API. Use input
preflight for configuration failures. Do not catch an analysis error and return
an empty finding list. Native `SourceKitFreeRule` remains available when the DSL
does not improve a rule.
