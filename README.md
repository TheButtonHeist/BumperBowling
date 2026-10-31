# Bumper Bowling

[![CI](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/TheButtonHeist/BumperBowling)](https://github.com/TheButtonHeist/BumperBowling/releases/latest)
[![License](https://img.shields.io/github/license/TheButtonHeist/BumperBowling)](LICENSE)

**Turn your Swift repository’s unwritten rules into rules everyone can run.**

Some decisions keep returning to code review.

A feature needs its own `State` and `Action`. Live services belong in bootstrap.
Every view needs a preview. Each route needs one registration.

The decisions are settled. People and agents still need reminders.

Bumper Bowling turns those decisions into Swift rules. Run them before review.
Run them in CI. Get a failure that points to the code and explains the repair.

You define the lane. The bumpers catch changes that leave it.

## One rule, one useful failure

Take a familiar convention: every feature view needs a preview.

```swift
struct CheckoutView: View {
    var body: some View {
        CheckoutForm()
    }
}
```

The compiler accepts this view. Your project can require a preview too:

```swift
import BumperBowlingCore
import SwiftSyntax

let swiftUIPreviews = Rules.each(
    structs().inheriting("View"),
    id: "app.swiftui_preview",
    summary: "Each feature view has a preview in the same file.",
    scope: .under("Sources/Features")
) { view in
    let previews = macroExpansions().named("Preview").matches(in: view.file)
    let viewName = view.node.name.text
    let hasPreview = previews.contains { preview in
        preview.node
            .descendants(of: FunctionCallExprSyntax.self)
            .map(\.calleeName)
            .contains(viewName)
    }

    return hasPreview ? [] : [view.failure(
        message: "\(viewName) needs a #Preview that constructs \(viewName)."
    )]
}
```

Add the rule to `BumperBowling.swift`:

```swift
let bumper = BumperProject {
    Included { "Sources" }
    Rules { swiftUIPreviews }
}
```

Then run `bumper lint .`:

```text
Sources/Features/Checkout/CheckoutView.swift:1:1
CheckoutView needs a #Preview that constructs CheckoutView. (app.swiftui_preview)
```

The rule has a purpose, a scope, and a repair. The same result serves a developer,
a reviewer, or an agent.

This example checks explicit `View` inheritance and constructor names inside a
`#Preview` in the same file. It does not resolve compiler type identity.

## The rule is yours

Rules can inspect any SwiftSyntax node type. Use a typed query for the nodes you
need, then ordinary Swift to describe the requirement.

Rules can require declarations, limit counts, protect boundaries, or compare
observations across files. A rule can require something to exist, as well as
report something that does not belong.

| Project convention | Expression |
| --- | --- |
| Each feature owns one state type and one action type | `Rules.each` over feature structs |
| One environment declaration across selected files | `Rules.assert` with `counting: .repository` |
| Each route has exactly one registration across files | `Rules.repository` with shared facts |
| A directory uses named analytics payloads | `Rules.forbid` over dictionary literal syntax |
| Live service construction stays in bootstrap code | `Rules.constructionOwnership` |
| Imports obey component dependencies | The architecture DSL and `DependencyBoundaries` |

The [rule recipes](docs/RULE_RECIPES.md) progress from a built-in boundary rule
to analysis across files and a derived call graph. Each example includes its
reason, scope, passing and failing fixtures, diagnostics, and limits.

Bumper Bowling supplies the queries, shared facts, evaluator, test support, and
reports. Your repository supplies the conventions.

## Ordinary Swift, all the way down

Start with a built-in factory for a policy it already expresses. Use
`Rules.each` for a requirement on each typed match. Use `Rules.repository` and
shared facts for relationships across files.

`SyntaxQuery<Node>` accepts any SwiftSyntax node type. A match keeps its typed
node, file, and source location. Common facts have direct access, such as
`variable.isMutable` and `variable.lexicalContext`.

For a custom walk, use a `SyntaxVisitor`. All these forms share the evaluator,
parsed syntax, fact cache, and reports.

The [authoring guide](docs/RULE_AUTHORING.md) covers the complete API.

## Add architecture where it helps

Syntax rules need no component declarations. Every included Swift file reaches
analysis, including files without an owner.

Architecture declarations add a vocabulary for ownership, imports, dependencies,
and recurring component patterns:

```swift
enum AppComponent: String, ComponentKey {
    case domain
    case checkout
}

let bumper = BumperProject {
    Included { "Sources" }

    Architecture(AppComponent.self) {
        Component(.domain) {
            Owns("Sources/Domain")
            Modules("Domain")
            MayUse(.foundation)
        }

        Component(.checkout) {
            Owns("Sources/Features/Checkout")
            Modules("CheckoutFeature")
            MayDependOn(.domain)
            MayUse(.foundation, .swiftUI)
        }
    }

    Rules {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        SourceCoverage(.error)
        AcyclicDeclaredDependencies(.error)
        swiftUIPreviews
    }
}
```

Components use your project’s names. `ComponentShape` and
`ComponentRequirement` can name recurring policies as the architecture grows.

Ownership checks remain separate from source discovery. `SourceCoverage` can
report missing or overlapping ownership while custom syntax rules still inspect
the included files.

## Start small. Keep the bumpers useful.

Start with one repeated review comment. Turn it into a rule with a clear repair.
Add rules as the project finds decisions worth protecting. Give each rule:

- A clear reason to exist.
- A scope where the convention applies.
- A diagnostic that explains the repair.
- A passing fixture and a failing fixture.

When the design changes, revise or remove the rule. Keep the rule, its explanation,
and its fixtures together.

People and agents read the same policy and receive the same failures. The bumpers
keep routine changes inside the project’s chosen lanes.

These are syntax checks. They do not resolve compiler identity or detect every
aliased call. Runtime tests remain necessary for behavior such as timeouts,
process handling, and cache safety.

## Get started

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/TheButtonHeist/BumperBowling.git",
        from: "0.7.0"
    )
]
```

Initialize the configuration:

```bash
swift run bumper init .
```

Add your rules to `BumperBowling.swift`.

Run the rules:

```bash
swift run bumper lint .
```

`BumperBowling.swift` is a Swift program, like `Package.swift`. Repository rule
sources can live in `.bumper/Sources`, with fixtures in `.bumper/Tests`.

The tool requires macOS 15 or later and Swift 6.2 or later. It can analyze source
that uses older Swift language modes.

## Put the bumpers in CI

Run the repository’s rule fixtures and source checks:

```bash
swift run bumper test .
swift run bumper lint .
```

`RuleTestHarness` evaluates rules against arrays of `SourceInput`. The
`BumperBowlingTestSupport` library supplies `ViolationMatcher` for diagnostic
assertions. The [authoring guide](docs/RULE_AUTHORING.md) shows the fixture pattern.

To adopt rules while existing violations remain, create a baseline:

```bash
swift run bumper baseline create . --output .bumper-baseline.json
swift run bumper lint . --baseline .bumper-baseline.json --fail-on error
```

The included [`compose-bumper-rules` skill](skills/compose-bumper-rules/SKILL.md)
guides agents through rule selection, composition, and fixtures.

## Commands

```text
bumper init [root]             Write a starter configuration.
bumper lint [root]             Check the repository.
bumper test [root]             Run repository rule tests.
bumper scan [root]             Show source inventory and dependencies.
bumper baseline create [root]  Write a JSON baseline.
bumper snapshot [root]         Show the declared architecture.
bumper config [root]           Check configuration loading.
bumper explain <path>          Show facts for one file.
```

## Documentation

- [Rule recipes](docs/RULE_RECIPES.md)
- [Rule authoring](docs/RULE_AUTHORING.md)
- [Built-in catalog](docs/built-ins/README.md)
- [Configuration language](docs/DSL_SPEC.md)
- [Build a rule from the ground up](docs/RULE_FROM_THE_GROUND_UP.md)
- [Architecture](docs/ARCHITECTURE.md)
- [SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md)

## Development

```bash
swiftlint lint --strict
BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift test
BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift run bumper test .
BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift run bumper lint .
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
