# Bumper Bowling

[![CI](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/TheButtonHeist/BumperBowling)](https://github.com/TheButtonHeist/BumperBowling/releases/latest)
[![License](https://img.shields.io/github/license/TheButtonHeist/BumperBowling)](LICENSE)

**Turn your Swift repository's unwritten rules into rules everyone can run.**

Your codebase relies on rules that the compiler cannot see.

A feature has `State`, `Action`, and `View`. Dependencies point toward Domain.
Only `AppBootstrap` constructs live services. Every SwiftUI view can be
constructed in at least one preview.

Those rules are architecture. When they live only in documentation and code
review, every developer or agent has to rediscover them.

Bumper Bowling turns them into Swift rules with source-level failures. You
define the lane. Bumper Bowling catches changes that leave it.

Take the preview rule. The compiler knows that `CheckoutView` conforms to
`View`, but it cannot require a preview that constructs it.

```swift
struct CheckoutView: View {
    var body: some View {
        CheckoutForm()
    }
}
```

Write that rule in Swift:

```swift
import BumperBowlingCore
import SwiftSyntax

let swiftUIPreviews = Rules.files(
    "app.swiftui_preview",
    summary: "Each SwiftUI view is constructed by at least one preview.",
    scope: .under("Sources/Features")
) { file in
    let views = structs().inheriting("View").matches(in: file)
    let previews = macroExpansions().named("Preview").matches(in: file)

    return views.compactMap { view in
        let viewName = view.node.name.text
        let hasPreview = previews.contains { preview in
            preview.node
                .descendants(of: FunctionCallExprSyntax.self)
                .map(\.calleeName)
                .contains(viewName)
        }

        return hasPreview ? nil : view.failure(
            message: "\(viewName) needs a #Preview that constructs \(viewName)."
        )
    }
}
```

```text
Sources/Features/Checkout/CheckoutView.swift:1:1
CheckoutView needs a #Preview that constructs CheckoutView. (app.swiftui_preview)
```

SwiftSyntax found the declarations, inheritance clause, macro, and constructor
call. Bumper Bowling composed those observations into one scoped rule with
source evidence.

That same composition can enforce the shape of an app.

## Give The Architecture A Vocabulary

Name the patterns that define the repository:

```swift
extension ComponentShape {
    static let feature = ComponentShape {
        MayUse(.foundation, .swiftUI)
        Requires(
            .explicitDomainSurfaces,
            .typedIdentity,
            .immutableStoredState
        )
        Declares("State", "Action", "View")
    }
}
```

Apply those patterns to real source:

```swift
enum AppComponent: String, ComponentKey {
    case domain
    case checkout
    case app
}

let bumper = BumperProject {
    Included { "Sources" }

    Architecture(AppComponent.self) {
        Component(.domain) {
            Owns("Sources/Domain")
            Modules("Domain")
            MayUse(.foundation)
            Requires(.pureDomain)
        }

        Component(.checkout) {
            Owns("Sources/Features/Checkout")
            Modules("CheckoutFeature")
            MayDependOn(.domain)
            Applies(.feature)
        }

        Component(.app) {
            Owns("Sources/App")
            Modules("App")
            MayDependOn(.domain, .checkout)
            MayUse(.foundation, .swiftUI, .networking)
        }
    }

    Rules {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
        swiftUIPreviews

        Rules.canonicalConstruction(
            "AppEnvironment",
            owners: .under("Sources/App/Bootstrap")
        )

        Rules.boundaryOnly(
            function: "JSONDecoder.decode",
            allowed: .under("Sources/Infrastructure/Decoding")
        )

        Rules.canonicalTraversal(
            root: "RouteTree",
            structuralCase: "branch",
            owners: .under("Sources/Navigation/Traversal")
        )
    }
}
```

This policy keeps dependencies pointed in the declared direction. It gives
every file one owner. It also protects construction, decoding, traversal, and
SwiftUI preview patterns.

The repository owns names such as `.feature` and `app.swiftui_preview`.
Bumper Bowling supplies the composition, evaluation, tests, and reports.

```text
SwiftSyntax -> typed observations -> scopes -> rules -> source evidence
```

## Start High. Drop Down When The Rule Demands It.

| Need | Use |
| --- | --- |
| Components, ownership, and dependencies | Architecture DSL |
| Reusable architecture patterns | `ComponentRequirement` and `ComponentShape` |
| Common ownership and construction rules | `Rules.*` shapers |
| Typed syntax matches | `SyntaxQuery` |
| Rules over each file | `Rules.files` |
| Repository-wide analysis | `BuiltInFacts` and `Rules.repository` |
| Full SwiftSyntax access | `Rules.visitor` and `SyntaxVisitor` |

Every level uses the same parser, scopes, rule protocol, and report. Built-in
rules and repository rules live in the same `Rules` block.

Read the [built-in catalog](docs/built-ins/README.md) to see every included
piece. Read [rule authoring](docs/RULE_AUTHORING.md) to build custom facts,
queries, visitors, and fixtures.

## Get Started

Add the package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/RoyalPineapple/BumperBowling.git", from: "0.6.0")
]
```

Initialize and validate the repository:

```bash
swift run bumper init .
swift run bumper lint .
```

`bumper init` writes `BumperBowling.swift`. This file is a Swift program, like
`Package.swift`.

Bumper Bowling can analyze repositories that use older Swift language modes.
The tool and its configuration currently require a Swift 6.2 toolchain.

## Put The Bumpers In CI

Your team declares the lanes. A developer or agent takes the shot. CI catches
a wild change and points it back toward the declared architecture.

```bash
swift run bumper lint .
```

Use a baseline to adopt rules without stopping current work:

```bash
swift run bumper baseline create . --output .bumper-baseline.json
swift run bumper lint . --baseline .bumper-baseline.json --fail-on error
```

Use focused fixtures for repository rules:

```bash
swift run bumper test .
```

Agents read the same architecture before editing and validate it afterward.
When the architecture changes, an agent can update the rule and its fixtures
with the source change.

The included [`compose-bumper-rules` skill](skills/compose-bumper-rules/SKILL.md)
guides that workflow.

## Commands

```text
bumper init [root]             Write a starter configuration.
bumper lint [root]             Validate the repository.
bumper test [root]             Run repository-owned rule tests.
bumper scan [root]             Show the observed architecture graph.
bumper baseline create [root]  Write a JSON baseline.
bumper snapshot [root]         Render the declared architecture.
bumper config [root]           Validate configuration loading.
bumper explain <path>          Show facts for one file.
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration language](docs/DSL_SPEC.md)
- [Built-in catalog](docs/built-ins/README.md)
- [Rule authoring](docs/RULE_AUTHORING.md)
- [Build a rule from the ground up](docs/RULE_FROM_THE_GROUND_UP.md)
- [SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md)

## Development

```bash
BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift test
swift run bumper lint .
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
