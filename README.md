# Bumper Bowling

[![CI](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/TheButtonHeist/BumperBowling/actions/workflows/ci.yml)

**Make your repository’s review conventions executable.**

Build your policies in Swift. Run them before review.

Every feature view needs a matching preview. Explicit coding keys cover stored
fields. Each route has one registration. These decisions are settled, but they
still return to code review.

Bumper Bowling gives them a readable Swift DSL, built on SwiftLintFramework and
SwiftSyntax. Your repository owns the policy. Builders compose the checks.
Typed queries select the syntax, and ordinary Swift handles the details.
SwiftLint runs each rule and reports the failures.

You define the lane. The bumpers catch changes that leave it.

## One convention, one readable rule

```swift
import BumperBowlingCore

enum SwiftUIPreviewRule: SyntaxRule {
    static let metadata = RuleMetadata(
        id: "app.swiftui_preview",
        summary: "Each feature view has a matching preview in the same file"
    )

    static var body: SyntaxCheck {
        Rules.forEach(structs().inheriting("View"), scope: .under("Sources/Features")) { view in
            Rules.require(
                inSameFile: macroExpansions().named("Preview")
                    .containing(functionCalls().named(view.name)),
                at: view,
                message: "\(view.name) needs a #Preview that constructs \(view.name)"
            )
        }
    }
}
```

The builder selects each view struct and requires a preview that constructs it.
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

A rule body combines checks. Use conditions, loops, and helper functions to
express the convention. Each requirement names the declaration to report.
Typed queries keep the source location and give you access to SwiftSyntax.

| Convention | Building blocks |
| --- | --- |
| A view has a matching preview | `Rules.forEach`, `Rules.require`, same-file and descendant queries |
| Explicit keys cover direct stored fields | Nested builders, direct-member queries, ordinary Swift sets |
| Each route has one registration across files | `Rules.repository`, typed collection, a validation builder |
| A repository-specific syntax convention | `SyntaxQuery<Node>` for any SwiftSyntax node, or a visitor inside `Rules.files` |

Each DSL rule is a distinct SwiftLint rule, with its own identifier. SwiftLint
owns execution, cached syntax, cross-file collection, and diagnostic reporting.
Bumper supplies the authoring language, test kit, starter, and command workflow.
Native SwiftLint rules can appear in the same project.

SwiftLint already supports these detection capabilities. Bumper’s purpose is to
make repository-owned conventions easier to express, test, and maintain.

See the [worked examples](docs/RULE_RECIPES.md) and [authoring guide](docs/RULE_AUTHORING.md).

## Start with one repeated review comment

Version 0.7.0 requires macOS 15 or later and Swift 6.4. It changes the public
API and package workflow. See the [migration guide](docs/MIGRATION.md) before
upgrading an existing configuration.

Build the tool from the release:

```bash
git clone --branch 0.7.0 https://github.com/TheButtonHeist/BumperBowling.git
cd BumperBowling
swift build --product bumper
```

Initialize the repository you want to check:

```bash
/path/to/BumperBowling/.build/debug/bumper init .
```

The starter depends on Bumper’s `main` branch. Commit the generated
`Package.resolved` to pin its revision. To use your own checkout during
development, add `--package-path /path/to/BumperBowling`. To keep the rules
package on this release, replace `branch: "main"` with `exact: "0.7.0"` in
`.bumper/Package.swift` before the first build.

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

The starter includes [passing and failing examples](Sources/BumperBowlingCore/Starter/Tests/BumperRulesTests/SwiftUIPreviewRuleTests.swift)
run through the public test harness and SwiftLint. Use them to preserve the
meaning of the convention as its implementation changes.

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
