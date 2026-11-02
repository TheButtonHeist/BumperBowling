# Three worked conventions

These examples show increasing complexity. They are syntax policies for a
repository, not universal Swift style requirements. Each has passing, failing,
and near-miss fixtures over the public harness.

## Match each view with its preview

The starter uses `Rules.forEach` to select view structs and `Rules.require`
to require a matching same-file preview. Descendant queries connect a preview
macro to its constructor calls.

- [Rule](../Sources/BumperBowlingCore/Starter/Sources/BumperRules/SwiftUIPreviewRule.swift)
- [Paired examples](../Sources/BumperBowlingCore/Starter/Tests/BumperRulesTests/SwiftUIPreviewRuleTests.swift)

A matching preview passes. A preview for another view, a constructor outside a
preview, and a preview in another file leave the requirement unsatisfied.
A view outside `Sources/Features` is outside this example’s scope.

It matches written `View` conformances and constructor names. It does not resolve
qualified types, aliases, or whether a preview executes a constructor.

## Cover direct stored fields with explicit keys

`Rules.forEach` builds checks for each explicitly `Codable` struct. Direct-member
queries find its own `CodingKeys`, cases, and stored instance properties. Ordinary Swift sets
identify missing keys.

- [Rule](../.bumper/Sources/BumperRules/ExplicitCodingKeysRule.swift)
- [Paired examples](../.bumper/Tests/BumperRulesTests/RuleRecipeTests.swift)

Computed, static, and nested properties do not require keys. Renamed raw values
are allowed. Types without explicit `CodingKeys` retain synthesized behavior.
A missing key reports at its property. A nested or other-file key cannot satisfy it.

This is an example convention. Swift permits intentional omission of fields;
repositories that do so should change the policy or omit this rule.

## Register each route exactly once

`Rules.repository` collects typed route cases and bare registrations from all
included files. Its validation builder emits a requirement for each route.
The subject scope selects `Sources/App/Routes.swift`.

- [Rule](../.bumper/Sources/BumperRules/RouteRegistrationsRule.swift)
- [Paired examples and subject failure](../.bumper/Tests/BumperRulesTests/RuleRecipeTests.swift)

One registration passes. Zero and two registrations fail at the route case.
`other.register(.detail)` is excluded. Another `AppRoute` outside the selected
file is not a subject. Removing the required subject file fails preflight.
A companion edit changes the next result because findings are not cached.

This matches a written enum name and bare `register(.case)` calls. It does not
prove that the resolved function registers that route at runtime.

## Protect Bumper’s own boundaries

The repository also tests four narrow policies: reuse parsed syntax, construct
processes in their owner file, launch and wait in named helpers, and keep engine
models immutable outside named implementation declarations.

- [Policies](../.bumper/Sources/BumperRules/BumperPolicies.swift)
- [Passing and failing examples](../.bumper/Tests/BumperRulesTests/BumperPolicyTests.swift)

Run `bumper test .` for repository recipes and policies. The journey check runs
the generated preview example and proves sharing through a second rule package.

## Retain source boundaries after migration

[Boundary recipes](../.bumper/Sources/BumperRules/BoundaryRecipes.swift) demonstrate
import ownership, complete ownership of scanned Swift files, named exported
contracts, and callback isolation. Their [paired examples](../.bumper/Tests/BumperRulesTests/BoundaryRecipeTests.swift)
run with `bumper test .`. They are examples to register in a consumer, not new
restrictions on Bumper's own source.

See [boundary migration](BOUNDARY_MIGRATION.md) for the syntax limits, unresolved
policies, and a direct native SwiftLint comparison.
