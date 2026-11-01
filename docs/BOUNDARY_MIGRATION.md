# Keep boundary policies small

The SwiftLint engine should remove consumer plumbing. These helpers preserve
common conventions without restoring components, a graph evaluator, or a fact
store. Each helper returns an ordinary `SyntaxCheck` inside a named rule.

## Imports and source ownership

```swift
public enum NetworkBoundary: SyntaxRule {
    public static let metadata = RuleMetadata(
        id: "app.network_boundary", summary: "Networking has a named owner"
    )
    public static var body: SyntaxCheck {
        Rules.importOwnership(
            ["Network", "FoundationNetworking"],
            allowed: .under("Sources/Transport").union(.files(["Sources/TLS.swift"]))
        )
    }
}
```

Use `Rules.forbiddenImports(["UIKit", "SwiftUI"], scope: .under("Sources/Domain"))`
for a boundary that cannot import UI. `imports(_:)` selects root module names;
`import struct Network.NWEndpoint` counts as importing `Network`. `NetworkExtras`
does not. Conditional branches are inspected as written.

`Rules.sourceOwnership` accepts the owner scopes, including exact-file owners
such as `.files(["Sources/TLS.swift"])`. It requires one owner per scanned Swift file. No owner and overlapping owners both
fail, including for empty files. Set its `scope:` when other included files,
such as tests, do not require an owner. Excluded and unscanned files are outside
this policy. It does not inventory Objective-C or prove build-target membership.
Owner paths are validated even if no source matches. Empty owner scopes are
allowed; the check does not require every owner to contain a Swift file.

Failures keep the native file, line, column, severity, and rule identifier.
Import failures also name the allowed locations and give a repair:

```text
Sources/Domain/Model.swift:1:1: error: Import Network is outside its allowed boundary. Allowed locations: (at or under "Sources/Transport") or ("Sources/TLS.swift"). Move the code that needs this import to an allowed location. (app.network_boundary)
```

Ownership failures distinguish missing owners from overlapping owners. A missing
owner lists the configured scopes. An overlap lists only the matching scopes.
Both failures give a repair. `RuleScope.description` retains unions and
exclusions. A custom predicate has the description `a custom scope` because
Bumper cannot infer allowed paths from arbitrary Swift code.

See the [executable boundary recipes](../.bumper/Sources/BumperRules/BoundaryRecipes.swift)
and [paired fixtures](../.bumper/Tests/BumperRulesTests/BoundaryRecipeTests.swift).
A repository can retain its own small component map and derive these checks from
it. Graph snapshots, dependency-cycle detection, and component configuration are
not reintroduced by these helpers.

## Inspect declaration contracts once

Every `DeclSyntaxProtocol` exposes:

- `explicitAccess`: written declaration access, using SwiftLint's `AccessControlLevel` and modifier helper. Setter-only modifiers do not change this value.
- `effectiveAccess`: `.resolved(AccessControlLevel)` or `.unresolved`.
- `contractTypes`: explicit parameter, return, property annotation, typealias,
  enum payload, and associated-type-default syntax.

`effectiveAccess` accounts for enclosing access caps, protocol requirements,
enum cases, extension defaults, and local declarations. A same-file extension
target must have one matching nominal declaration. An unknown or ambiguous
extension target and an override without explicit access stay unresolved.
It does not infer types, inherited access, macro output, or compiler identity.

`contractTypes` does not synthesize types for inferred properties or expand
aliases. Shared binding annotations occur once in this declaration-level list.
`lexicalPlacement` distinguishes file scope, type members, and local scratch;
a field in a local type is still a type member.

The named-contract recipe uses these facts to reject multi-value tuple syntax
in exported contracts. It explicitly reports unresolved access. Repositories
may choose another uncertainty policy, but should state it and test it.

## Inspect an outer callback type

`file.resolveType(type)` returns `.resolved(LexicalType)` or
`.unresolved(LexicalTypeFailure)`. A resolved value retains the outer syntax,
optional status, outer attributes, followed aliases, and any same-file nominal
declaration. Its `function` property identifies an outer function type.
Attributes on a nested callback parameter do not isolate the containing callback.

Resolution supports optional and parenthesized wrappers and explicit file-local
aliases in the nearest lexical scope. Qualified members of a uniquely resolved,
nongeneric same-file nominal are supported. Type names are looked up separately
from variable and function names. Generic parameters shadow outer aliases,
including inside extensions of same-file types. Extension lookup inspects the
target's own member scope before file-level aliases. It also follows enclosing
extension targets. Matching members in other extensions remain unresolved
instead of selecting a file-level alias. Extension scope expansion stops after
32 targets. Unknown extension targets stay
unresolved. Function-local and closure-local types cannot supply an extension target.

Imported names, inherited or extension-provided qualified members, generic
substitutions, and unsupported syntax stay unresolved. Duplicate conditional
aliases are ambiguous. Cycles have a distinct failure. Reusing a qualified owner
alias is allowed and still consumes the alias budget. Resolution stops at the default 32-alias bound
or a fixed 256-step bound for each outer-type walk. Wrappers and aliases use a
loop. Qualified-owner recursion has a separate 32-level bound. Syntax from another file context is rejected. This is a bounded syntax
walk over SwiftLint's existing tree; it creates no parser or shared cache.

Resolve an attribute's `attributeName` through the same method. A resolved
`isGlobalActor` means its same-file declaration is marked `@globalActor`.
It does not establish compiler validity. Imported actors such as `MainActor`
need an explicit repository spelling policy. Actor-like suffixes supply no fact.

The callback recipe checks optional function slots and `onFoo` callbacks. It
permits other nonoptional dependency functions. It leaves unresolved imported
callback types to the compiler because it has no evidence of a function shape.
This is a deliberate policy choice, unlike the named-contract recipe's handling
of unknown access.

## Compare against direct SwiftLint

[NativeComparisonTests.swift](../Tests/BumperBowlingTestSupportTests/NativeComparisonTests.swift)
implements the same UI import convention through a Bumper helper and a native
`SourceKitFreeRule` with its own SwiftSyntax visitor. Both execute the same
fixtures and must produce identical native findings, including locations,
severity, repair text, selective imports, conditional branches, and disable
commands. Run it with:

```sh
swift test --filter boundaryHelperMatchesDirectSwiftLintDiagnostics
```

The Bumper author type expresses the check in one body line. The native version
owns a visitor, configuration, selection, and diagnostic construction. This
comparison establishes diagnostic parity and shows the consumer code removed.
It does not establish faster builds, faster lint, or lower maintenance costs.
Measure cold builds, warm edits, and lint separately before making those claims.

## Toolchain costs

This change retains the verified Swift 6.4, SwiftLint 0.63.3, and SwiftSyntax
604 pair. Lowering the minimum requires compiling and running these checks on an
older toolchain; editing the manifest alone does not establish support. Keep
rules in their own `.bumper` package so this requirement does not raise the
application's deployment target or add lint dependencies to its product graph.
