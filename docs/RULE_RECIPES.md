# Rule Recipes

These five recipes use public APIs and ordinary Swift. Paired passing and
failing fixtures live in [RuleAuthoringRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/RuleAuthoringRecipeTests.swift)
and [PatternAuthoringTests.swift](../Tests/BumperBowlingTestSupportTests/PatternAuthoringTests.swift).
CI runs these fixtures with the package tests. Syntax-only fixtures do not need
component declarations.

Rules share parsed syntax and the existing evaluator. They do not establish
compiler type identity or runtime behavior.

## Arbitrary syntax

This policy requires named analytics payloads instead of dictionary literals.
No dedicated dictionary query helper is necessary.

```swift
import BumperBowlingCore
import SwiftSyntax

let namedPayloads = Rules.forbid(
    SyntaxQuery<DictionaryExprSyntax>(),
    id: "analytics.named_payloads",
    summary: "Analytics payloads use named types.",
    scope: .under("Sources/Analytics")
) { _ in
    "Use a named analytics payload instead of a dictionary literal."
}
```

The passing fixture uses a named payload and permits dictionaries outside
analytics. The failing fixture reports a dictionary literal inside analytics.
This rule inspects literal syntax. It does not identify all dictionary values.

## Requirements inside each type

This project defines a feature as a struct whose name ends in `Feature`.
Each feature needs direct `State` and `Action` declarations.

```swift
let featureMembers = Rules.each(
    structs().filter { $0.node.name.text.hasSuffix("Feature") },
    id: "features.direct_members",
    summary: "Each feature declares its own State and Action."
) { feature in
    let names = feature.node.memberBlock.members.compactMap { member in
        member.decl.as(StructDeclSyntax.self)?.name.text
            ?? member.decl.as(EnumDeclSyntax.self)?.name.text
    }
    return ["State", "Action"].filter { !names.contains($0) }.map { missing in
        feature.failure(
            message: "\(feature.node.name.text) needs a direct \(missing) declaration.",
            evidence: ViolationEvidence(
                observed: feature.node.name.text,
                expectation: "direct State and Action declarations"
            )
        )
    }
}
```

The closure receives a typed `SyntaxMatch<StructDeclSyntax>` and can return
multiple failures. No wrapper around SwiftSyntax is necessary.

The fixtures cover multiple features in one file. A declaration inside a
feature's nested type cannot satisfy the requirement. An unrelated type cannot
supply another feature's missing member.

This rule accepts direct structs or enums with the required names. It does not
require that a feature exists. It does not combine members from extensions.
`Rules.assert` can express a separate requirement for declaration presence.

## Relationships across files

This project declares routes as direct cases of `enum AppRoute`. Each case
needs exactly one bare `register(.caseName)` call across the selected sources.

The [complete recipe](../Tests/BumperBowlingTestSupportTests/RuleAuthoringRecipeTests.swift)
derives a `RouteInventory` with the existing `DerivedFact` API. It collects:

- Each direct enum case and its source location.
- Each bare `register` call with one argument of the form `.caseName`.

The repository rule compares these observations:

```swift
let routeRegistrations = Rules.repository(
    "routes.registration",
    summary: "Each AppRoute case has exactly one explicit registration.",
    scope: .files(["Sources/App/Routes.swift"])
) { subjects, context in
    let paths = Set(subjects.map(\.path))
    let inventory = try context.facts(routeInventory)
    let counts = Dictionary(grouping: inventory.registrations, by: { $0 })
        .mapValues(\.count)
    return inventory.cases.filter { paths.contains($0.file.path) }.compactMap { route in
        let name = route.node.name.text
        let count = counts[name, default: 0]
        guard count != 1 else { return nil }
        return route.failure(
            message: "\(name) needs exactly one registration; found \(count).",
            evidence: ViolationEvidence(
                observed: "\(name): \(count) registrations",
                expectation: "one bare register(.\(name)) call"
            )
        )
    }
}
```

The passing fixture places registrations in separate files. The failing
fixture has a duplicate registration and a missing registration. An unrelated
receiver call, `other.register(.detail)`, cannot satisfy the requirement.

Only the selected route file supplies subjects. Shared facts retain registration
calls from other files. An unrelated `AppRoute` declaration outside the selected
file does not need registrations under this rule. Diagnostics anchor the
selected route cases.

The matching convention is explicit syntax. The rule does not resolve overloads,
aliases, conditional execution, or runtime registration. It does not reject
registration names absent from `AppRoute`. It does not require `AppRoute` to
exist. Those are separate policies.

## A repository-wide count

This convention permits exactly one struct whose name ends in `Environment`
across the selected source files.

```swift
Rules.assert(
    structs().filter { $0.node.name.text.hasSuffix("Environment") },
    cardinality: .exactly(1),
    counting: .repository,
    id: "environments.one",
    summary: "One environment struct per counting unit."
)
```

`environmentCountSeparatesSelectionFromAggregation` in
[PatternAuthoringTests.swift](../Tests/BumperBowlingTestSupportTests/PatternAuthoringTests.swift)
demonstrates both counting modes. Repository counting accepts one environment
and an unrelated file. It reports a second environment in another file at that
declaration's location. Per-file counting applies the requirement independently.

The repair is to consolidate environment declarations or narrow the selected
files to the intended application. This is a naming convention, not compiler
type identity. A project with several independent applications needs a separate
scope for each application. Remove this rule if that convention no longer fits.

## A component policy

This project permits imports of `UI` only from its `ui` component.

```swift
enum AppComponent: String, ComponentKey { case ui }

let uiImports = Rules.importOwnership(
    ["UI"],
    allowed: .component(AppComponent.ui),
    id: "components.ui_imports"
)
```

The public-harness fixtures accept the import in an owned UI source. They
report the import in a domain source and in an unowned source. Missing ownership
never grants permission to enter a component scope.

The repair is to remove the import or move the UI code into its component.
Architecture declarations supply real path ownership. Component dependency
rules can also compare imports with the declared dependency graph.

This recipe matches the explicit module spelling `UI`. It does not discover
compiler build targets or infer dependencies from symbol use. Remove this rule
if the project no longer separates UI imports by component.

## Adoption and removal

These are example policies, not rules that every Swift project must adopt.
Named shapers cannot express the direct-member and cross-file relationships
without the custom queries in these recipes.

The feature recipe replaces its original per-file query loop with `Rules.each`.
The dictionary recipe demonstrates the generic query in place of a dedicated
query-root helper. The route recipe retains ordinary Swift for matching.

The repairs are local: use a named analytics payload, declare the missing direct
member, or add exactly one explicit route registration.

If a project adopts a different payload model, feature shape, or route convention,
remove or revise the corresponding rule and fixtures together.
