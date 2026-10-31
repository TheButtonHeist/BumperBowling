# Bumper Bowling

[![CI](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml)

**Make your repository’s review conventions executable.**

Write them in Swift. Test them with examples. Run them before review.

Every feature view needs a matching preview. Explicit coding keys cover stored
fields. Each route has one registration. These decisions are settled, but they
still return to code review.

Bumper Bowling gives them a readable Swift DSL, built on SwiftLintFramework and
SwiftSyntax. Your repository owns the rules and their examples. SwiftLint runs
each rule and reports the failures.

You define the lane. The bumpers catch changes that leave it.

## One convention, one readable rule

```swift
import BumperBowlingCore

struct SwiftUIPreviewRule: SyntaxRule {
    var configuration = RuleSettings<Self>()
    static let metadata = RuleMetadata(
        id: "app.swiftui_preview",
        summary: "Each feature view has a matching preview in the same file"
    )

    var body: SyntaxCheck {
        Rules.forbid(
            structs().inheriting("View").without(inSameFile: { view in
                macroExpansions().named("Preview")
                    .containing(functionCalls().named(view.name))
            }),
            scope: .under("Sources/Features")
        ) { view in
            "\(view.name) needs a #Preview that constructs \(view.name)"
        }
    }
}
```

The rule selects view structs that lack a preview containing their constructor.
A preview for another view, a constructor outside a preview, or a preview in
another file cannot satisfy it.

Register it in the repository’s runner:

```swift
BumperProject(included: ["Sources"]) {
    SwiftUIPreviewRule.self
}.main()
```

A missing preview produces a normal SwiftLint diagnostic:

```text
Sources/Features/DocumentView.swift:1:1: error: app.swiftui_preview Violation: DocumentView needs a #Preview that constructs DocumentView (app.swiftui_preview)
```

These are syntax checks. The example matches a written `View` conformance and
constructor name. It does not resolve aliases or compiler identity.

## Small rules. Full Swift when you need it.

The DSL provides queries, file scopes, and useful diagnostic locations.
Ordinary Swift supplies the policy logic.

| Convention | Building blocks |
| --- | --- |
| A view has a matching preview | `Rules.forbid`, same-file and descendant queries |
| Explicit keys cover direct stored fields | `Rules.each`, direct-member queries, ordinary Swift sets |
| Each route has one registration across files | `Rules.repository`, typed per-file collection |
| A repository-specific syntax convention | `SyntaxQuery<Node>` for any SwiftSyntax node, or a visitor inside `Rules.files` |

Each DSL rule is a distinct SwiftLint rule, with its own identifier. SwiftLint
owns execution, cached syntax, cross-file collection, and diagnostic reporting.
Bumper supplies the authoring language, test kit, starter, and command workflow.
Native SwiftLint rules can appear in the same project.

SwiftLint already supports these detection capabilities. Bumper’s purpose is to
make repository-owned conventions easier to express, test, and maintain.

See the [worked examples](docs/RULE_RECIPES.md) and [authoring guide](docs/RULE_AUTHORING.md).

## Start with one repeated review comment

This branch contains an unreleased, breaking update. It requires macOS 15 or
later and Swift 6.4. See the [migration guide](docs/MIGRATION.md) for existing configurations.

Build the tool from this checkout:

```bash
swift build --product bumper
```

Initialize the repository you want to check:

```bash
/path/to/BumperBowling/.build/debug/bumper init . --package-path /path/to/BumperBowling
```

The explicit package path uses your checkout during development. Without it,
the starter depends on Bumper’s `main` branch. Commit the generated
`Package.resolved` to pin its revision. After this update reaches `main`, other
repositories can use that default.

The starter is an ordinary Swift package:

```text
.bumper/
  Package.swift
  Sources/BumperRules/SwiftUIPreviewRule.swift
  Sources/BumperRulesRunner/main.swift
  Tests/BumperRulesTests/SwiftUIPreviewRuleTests.swift
```

Edit the rule and its passing and failing examples. Set the runner’s `included`
paths to your source roots. Update the rule’s scope if your feature views live
elsewhere. Once `bumper` is on your path, run:

```bash
bumper test .
bumper lint .
```

## Prove the convention with examples

The starter includes paired fixtures evaluated through the same rule type:

```swift
let harness = RuleTestHarness(SwiftUIPreviewRule.self)
let passing = try harness.evaluate([
    .swift("Sources/Features/DocumentView.swift", source: """
    struct DocumentView: View {}
    #Preview { DocumentView() }
    """),
])
#expect(passing.isEmpty)
```

The failing example asserts the finding count, identifier, path, location,
severity, and repair message. The [complete starter test](Sources/BumperBowlingCore/Starter/Tests/BumperRulesTests/SwiftUIPreviewRuleTests.swift)
includes the near misses too.

The public harness uses SwiftLint’s execution path. It supports named files,
multiple files, and ordinary Swift Testing assertions.

## Keep the rule with the decision

Commit `.bumper`’s package, rules, tests, and lockfile. Review them together.
Use the same commands in CI:

```bash
bumper test .
bumper lint .
```

SwiftPM recompiles changed rule source and reuses dependency builds. Bumper
recomputes findings on every run. It does not persist violation results.

To share conventions, export public rule types from a named Swift package.
Other repositories import that package and register the rules they want.
There is no separate rule registry or distribution format.

Keep each convention small and give its diagnostic a clear repair. When a
decision changes, change or delete the rule and its examples together.

## Execution and limits

Builds and tests run trusted Swift programs with normal process access.
`bumper lint` runs the compiled rules with no writes or network access. It passes
only `TOOLCHAIN_DIR` in the environment. Direct `swift run` bypasses that boundary.

Lint builds have a ten-minute timeout. Rule execution defaults to 60 seconds,
with bounded output. Source input has file, byte, UTF-8, and path checks.
These checks do not replace runtime tests for application behavior.

Error findings exit 1. Host failures exit 2. Warnings exit 0. Tests preserve the
Swift test process’s status. See [architecture and contracts](docs/ARCHITECTURE.md).

## Development

```bash
swiftlint lint --strict
swift test
swift run bumper test .
swift run bumper lint .
Scripts/verify-rule-journey.sh
```

The journey check builds a fresh starter, runs its fixtures, edits a rule,
checks dependency-build reuse, and consumes a shared rule from another package.

Apache License 2.0. See [LICENSE](LICENSE).
