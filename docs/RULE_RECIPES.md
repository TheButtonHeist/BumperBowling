# Rule Recipes

These examples progress from one built-in rule to analysis across files and a
derived call graph. Each policy solves a stated project problem. The examples
are conventions to adapt, rather than defaults for every Swift project.

| Step | Project decision | Capability |
| --- | --- | --- |
| 1 | Parsing belongs to adapters | One built-in boundary rule |
| 2 | Analytics uses named payloads | An arbitrary SwiftSyntax query |
| 3 | Each feature owns one state and one action type | Requirements and counts inside each declaration |
| 4 | One environment declaration serves this app | A count across selected files |
| 5 | Each route has one registration | A shared fact and a relationship across files |
| 6 | One subsystem owns recursive traversal | A derived call graph |

The complete rule code and paired fixtures live in
[RuleAuthoringRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/RuleAuthoringRecipeTests.swift).
The count fixtures live in
[PatternAuthoringTests.swift](../Tests/BumperBowlingTestSupportTests/PatternAuthoringTests.swift).
Run them with:

```bash
swift test --filter 'RuleAuthoringRecipeTests|PatternAuthoringTests'
```

CI runs these tests through public imports and `RuleTestHarness`. Each pair
uses the same rule instance. Failing fixtures assert the rule ID, path, count,
and available source location or diagnostic evidence. The fixtures stay outside
production scan roots.

Rules reuse parsed syntax and shared facts. These are syntax checks. They do
not establish compiler identity or runtime behavior.

## 1. A built-in boundary rule

This project parses Swift at its adapters. Other code reuses parsed syntax.

```swift
import BumperBowlingCore

let parsingBoundary = Rules.boundaryOnly(
    function: "Parser.parse",
    allowed: .under("Sources/Parsing"),
    id: "app.parsing_boundary"
)
```

`parsingStaysAtTheDeclaredBoundary` accepts a parse call inside the adapter and
use of `file.syntax` outside it. Moving the parse call into a rule file produces
one diagnostic at that call:

```text
Sources/Rules/Policy.swift:2:9
Parser.parse is called outside its boundary. (app.parsing_boundary)
```

The repair is to reuse the parsed input or move parsing into the adapter.
The matcher recognizes explicit call spellings. It does not detect every alias.

## 2. An arbitrary syntax query

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

## 3. Requirements inside each declaration

This project defines a feature as a struct whose name ends in `Feature`.
Each feature needs one direct struct or enum ending in `State`, and one ending
in `Action`. Two distinct state types are valid Swift, but violate this convention.

```swift
let featureMembers = Rules.each(
    structs().filter { $0.node.name.text.hasSuffix("Feature") },
    id: "features.direct_members",
    summary: "Each feature declares one direct state type and one direct action type."
) { feature in
    let names = feature.node.memberBlock.members.compactMap { member in
        member.decl.as(StructDeclSyntax.self)?.name.text
            ?? member.decl.as(EnumDeclSyntax.self)?.name.text
    }
    return ["State", "Action"].compactMap { suffix in
        let count = names.filter { $0.hasSuffix(suffix) }.count
        guard count != 1 else { return nil }
        return feature.failure(
            message: "\(feature.node.name.text) needs one direct *\(suffix) declaration; found \(count).",
            evidence: ViolationEvidence(
                observed: "\(feature.node.name.text): \(count) direct *\(suffix) declarations",
                expectation: "one direct *State and one direct *Action declaration"
            )
        )
    }
}
```

`everyFeatureHasItsOwnDirectMembers` accepts two valid features. Its failing
fixture includes missing members, members hidden inside a nested type, and two
state types inside one feature. It reports four failures on the owning features.
An unrelated declaration cannot supply a missing member.

The same fixtures run with declarations together and in separate files. The
same declarations produce the same policy failures. Paths and source locations
follow each file. The unit of this policy is a feature declaration.

Example diagnostic:

```text
Sources/Features/Features.swift:3:1
PaymentFeature needs one direct *State declaration; found 2. (features.direct_members)
```

The repair is to place the required types directly inside their feature and
remove the ambiguous second state type. The rule does not combine extensions or interpret macros and conditional
compilation. It does not inspect state behavior or require that a feature
exists. A separate `Rules.assert` can require declaration presence.

This example replaces file-based model heuristics. `Rules.each` also supports a
project's own per-model property budget or per-enum case requirement. No special
state-machine factory is necessary for that syntax inspection.

## 4. A repository-wide count

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

## 5. Relationships across files

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

## 6. A derived call graph

This project gives `Sources/Traversal` ownership of recursive `Tree` traversal.
A second traversal duplicates a decision that the project wants to centralize.

```swift
let treeTraversal = Rules.canonicalTraversal(
    root: "Tree",
    structuralCase: "branch",
    owners: .under("Sources/Traversal"),
    id: "tree.traversal_owner"
)
```

The factory uses `BuiltInFacts.recursiveCallGroups`. The provider connects
locally dispatched calls and finds direct or mutual recursion. The policy then
requires a `.branch` case pattern against a `Tree` parameter or a matching `self`.

`recursiveTraversalHasAnExplicitOwner` accepts traversal inside the owner and a
non-recursive inspection outside it. Its failing fixture adds recursive search
outside the owner and reports the function declaration:

```text
Sources/Features/Search.swift:1:1
search recursively traverses Tree.branch outside its owners. (tree.traversal_owner)
```

The repair is to reuse the owned traversal or move the implementation into its
owner. This is a specialized policy for a project that centralizes traversal.
It is not a general rule against recursion.

The call graph uses names and local-dispatch syntax. It does not resolve compiler
identity, overloads, aliases, dynamic dispatch, or iterative traversal. The
[expanded example](RULE_FROM_THE_GROUND_UP.md) shows the fact derivation and policy
separately. Existing tests also cover mutual recursion, unrelated case subjects,
and calls on another receiver.

## Add component policy where it helps

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

## The README example

`readmePreviewRuleHasPassingAndFailingFixtures` runs the README's preview rule.
It accepts a preview in the view's file and ignores views outside the selected
scope. A preview in another file does not satisfy the rule. The failing fixture
reports the view declaration, with its rule ID, path, location, and repair message.

This example recognizes explicit inheritance and constructor names inside
`#Preview`. It does not prove that a preview renders successfully.

## An explicit nominal-name query

`reservedSuffixAppliesOnlyToNominalDeclarations` replaces the former
`singleNominalSpelling` helper with a visible choice of syntax:

```swift
let expressionOwners = Rules.forbid(
    nominalDeclarations().filter {
        $0.node.asProtocol(NamedDeclSyntax.self)?.name.text.hasSuffix("Expr") == true
    }.excluding(.under("Sources/Expressions")),
    id: "expressions.owners",
    summary: "Expression declarations belong to the expression subsystem."
) { _ in
    "Declarations ending in Expr belong in Sources/Expressions."
}
```

The passing fixture permits an expression type inside its owner. Functions and
variables with the suffix do not count as nominal declarations. A `CallExpr`
struct outside the owner produces one failure at that declaration.

The rule reserves a naming convention and an owner. It does not require one
unique declaration. `Rules.singleDeclaration` serves that separate purpose.

## Adoption and removal

Each example has an explicit project decision, selection rule, repair, and limit.
Use stable project-specific IDs when composing several instances of one factory.

When the project changes its payload model, feature structure, route convention,
or traversal ownership, revise or remove the corresponding rule and fixtures.
