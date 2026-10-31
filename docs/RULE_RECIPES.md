# Rule Recipes

These examples progress from one built-in rule to analysis across files and a
derived call graph. Each policy solves a stated project problem. The examples
are conventions to adapt, rather than defaults for every Swift project.

| Step | Project decision | Capability |
| --- | --- | --- |
| 1 | Parsing belongs to adapters | One built-in boundary rule |
| 2 | Unchecked sendability stays in synchronization adapters | An arbitrary SwiftSyntax query |
| 3 | Each selected value type offers both union operations | Requirements inside each declaration |
| 4 | Count selected declarations across files | A count across selected files |
| 5 | Each route has one registration | A shared fact and a relationship across files |
| 6 | One subsystem owns recursive traversal | A derived call graph |

The complete rule code and paired fixtures live in
[RuleAuthoringRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/RuleAuthoringRecipeTests.swift).
The source-backed Swift examples live in
[SwiftPracticeRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/SwiftPracticeRecipeTests.swift).
Their rationale and primary sources are in [Swift practices](SWIFT_PRACTICES.md).
The count fixtures live in
[PatternAuthoringTests.swift](../Tests/BumperBowlingTestSupportTests/PatternAuthoringTests.swift).
Run them with:

```bash
swift test --filter 'SwiftPracticeRecipeTests|RuleAuthoringRecipeTests|RelatedRuleRecipeTests|QueryCompositionTests|PatternAuthoringTests'
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

### Controllable dependencies

[Point-Free's dependency examples](https://github.com/pointfreeco/swift-dependencies)
show why clocks and other external inputs need control in tests. This example
uses Swift's existing `Clock` protocol and adds no dependency.

```swift
let controllableClocks = Rules.constructionOwnership(
    "ContinuousClock", allowed: .under("Sources/Dependencies"), id: "dependencies.clock"
)
```

`clocksAreConstructedAtTheDependencyBoundary` accepts clock construction in the
adapter and a generic function that receives a clock. Constructing one directly
inside the library reports the call's location. Both versions compile.

The repair is to pass a clock into the library function. This rule matches the
explicit constructor spelling. It does not detect aliases, other clock types,
`Date.now`, or every way to obtain time. It does not prove deterministic behavior.

## 2. An arbitrary syntax query

The [Swift concurrency guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/#Manual-Synchronization)
explains unchecked sendability for manual synchronization. This project keeps
those conformances in `Sources/Synchronization` for focused review.

```swift
import BumperBowlingCore
import SwiftSyntax

let uncheckedSendableBoundary = Rules.forbid(
    SyntaxQuery<AttributedTypeSyntax>().filter { type in
        ["Sendable", "Swift.Sendable"].contains(type.node.baseType.trimmedDescription)
            && type.node.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "unchecked" }
    }.excluding(.under("Sources/Synchronization")),
    id: "concurrency.unchecked_boundary",
    summary: "Unchecked Sendable conformances belong to manually synchronized adapters."
) { _ in
    "Keep manually synchronized Sendable conformances in Sources/Synchronization."
}
```

`uncheckedConformancesStayAtTheSynchronizationBoundary` accepts a lock-protected
class inside that boundary. Actors and checked `Sendable` values remain allowed
elsewhere. Moving the same class outside the boundary produces a diagnostic on
`@unchecked Sendable`. Qualified `Swift.Sendable` syntax also matches.

The repair is to use a checked conformance when possible, or put the manually
synchronized adapter inside its owner. Moving code does not prove thread safety.
The rule checks written attributes and the two explicit type spellings. Aliases,
macro output, and actual synchronization behavior remain outside this check.

## 3. Requirements inside each declaration

[Swift's naming guidance](https://www.swift.org/documentation/api-design-guidelines/#strive-for-fluent-usage)
describes consistent mutating and nonmutating counterparts. This library makes
one additional choice: selected structs with an explicit in-place union operation
also provide the corresponding value-returning operation.

```swift
import BumperBowlingCore
import SwiftSyntax

let valueOperationPairs = Rules.each(
    structs(), id: "api.value_operations",
    summary: "Selected value types offer matching in-place and value-returning union operations.",
    scope: .under("Sources/Values")
) { value in
    let methods = functions().members(of: value).map(\.node)
    return methods.compactMap { method -> RuleFailure? in
        let parameters = method.signature.parameterClause.parameters
        guard method.name.text == "formUnion", method.modifiers.contains(where: { $0.name.text == "mutating" }),
              parameters.count == 1, let parameter = parameters.first, parameter.type.trimmedDescription == "Self", parameter.firstName.text == "_",
              method.signature.returnClause == nil else { return nil }
        let hasCopy = methods.contains { candidate in
            let inputs = candidate.signature.parameterClause.parameters
            return candidate.name.text == "union"
                && !candidate.modifiers.contains { ["mutating", "static", "class"].contains($0.name.text) }
                && inputs.count == 1 && inputs.first?.firstName.text == parameter.firstName.text
                && inputs.first?.type.trimmedDescription == "Self"
                && candidate.signature.returnClause?.type.trimmedDescription == "Self"
        }
        return hasCopy ? nil : SyntaxMatch(node: method, file: value.file).failure(
            message: "Provide union(_:) -> Self alongside formUnion(_:).",
            evidence: ViolationEvidence(
                observed: "formUnion(_:) has no matching value-returning union(_:)",
                expectation: "a nonmutating instance method union(_ other: Self) -> Self on the same struct"
            )
        )
    }
}
```

`valueOperationsBelongToTheSameType` accepts a pair on the same struct. Its
failing fixtures cover a missing counterpart, a nested helper, a mutating copy,
a wrong return type, a wrong parameter type, and a static method. Each reports
one diagnostic on the in-place method. Another type cannot supply the counterpart.

The same cases run with declarations together and in separate files. The unit
of the policy is a struct, independent of file layout.

Example diagnostic:

```text
Sources/Values/Selection.swift:2:5
Provide union(_:) -> Self alongside formUnion(_:). (api.value_operations)
```

The repair is to declare the matching instance method on that struct. Selection
is limited to `Sources/Values`. The rule recognizes a direct, explicitly mutating
`formUnion(_:)` with one `Self` parameter and no return clause. Its counterpart
must be a nonmutating instance `union(_:)` taking and returning explicit `Self`.
It does not combine extensions, resolve aliases or generic constraints, interpret
conditional compilation, or prove that both operations have equivalent behavior.
Requiring both forms is this library's policy, not a requirement for all Swift types.

## 4. A repository-wide count

This counting example selects structs whose names end in `Adapter`. It compares
per-file counts with one combined repository count. It demonstrates aggregation;
it does not recommend one adapter for every project.

```swift
Rules.assert(
    structs().filter { $0.node.name.text.hasSuffix("Adapter") },
    cardinality: .exactly(1),
    counting: .repository,
    id: "adapters.one",
    summary: "One adapter struct per counting unit."
)
```

`matchCountSeparatesSelectionFromAggregation` in
[PatternAuthoringTests.swift](../Tests/BumperBowlingTestSupportTests/PatternAuthoringTests.swift)
demonstrates both counting modes. Repository counting accepts one adapter
and an unrelated file. It reports a second adapter in another file at that
declaration's location. Per-file counting applies the requirement independently.

For an actual project, choose the declaration predicate, scope, and count that
express its requirement. Suffix matching is a naming convention, not compiler
type identity. The mechanics do not prescribe a repository architecture.

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

## Related syntax in three small rules

These examples use the same selection, navigation, and reporting APIs at three
levels. They add no custom visitor or second evaluator.

### Each feature view has a preview

```swift
import BumperBowlingCore

let swiftUIPreviews = Rules.forbid(
    structs().inheriting("View").without(inSameFile: { view in
        macroExpansions().named("Preview")
            .containing(functionCalls().named(view.name))
    }),
    id: "app.swiftui_preview",
    summary: "Each feature view has a preview in the same file.",
    scope: .under("Sources/Features")
) { view in
    "\(view.name) needs a #Preview that constructs \(view.name)."
}
```

`previewRuleHasPassingAndFailingFixtures` in
[RuleAuthoringRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/RuleAuthoringRecipeTests.swift)
accepts a preview that constructs each selected view. It ignores out-of-scope
views. An unrelated preview, a constructor outside a preview, or a preview in
another file cannot satisfy the rule. The failure points to the view declaration.

The repair is to add a matching preview in that file. This example recognizes
structs with explicit `View` inheritance and written constructor names inside
`#Preview`. It does not resolve aliases, qualified names, inferred conformances,
or whether the preview renders successfully. The scope chooses which views
need previews.

### Previews avoid live factories

```swift
let previewDependencies = Rules.forbid(
    macroExpansions().named("Preview").containing(functionCalls().named("Client.live")),
    id: "ui.preview_dependencies",
    summary: "Previews use sample clients."
) { _ in
    "Use a sample client in this preview."
}
```

`previewsDoNotCreateLiveClients` in
[RelatedRuleRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/RelatedRuleRecipeTests.swift)
accepts sample clients inside previews and live calls elsewhere. Two forbidden
calls inside one preview produce one failure on that preview.

The repair is to supply the sample client. This policy recognizes the configured
`Client.live` spelling. It does not prove that sample data performs no I/O or
catch every way to construct a live dependency.

### Explicit coding keys cover stored fields

This project requires explicit `CodingKeys` to list each direct stored instance
property. Types without `CodingKeys` retain Swift's automatic synthesis.
Swift permits a default-valued property to be omitted from coding keys. That
omission can silently exclude a field this project expects to persist.

```swift
import BumperBowlingCore
import SwiftSyntax

let explicitCodingKeys = Rules.each(
    structs().inheriting("Codable"),
    id: "persistence.coding_keys",
    summary: "Explicit CodingKeys covers each stored instance property.",
    scope: .under("Sources/Persistence")
) { model in
    let keys = SyntaxQuery<EnumDeclSyntax>().filter { $0.name == "CodingKeys" }.members(of: model)
    guard let keys = keys.first else { return [] }
    let cases = SyntaxQuery<EnumCaseDeclSyntax>().members(of: keys)
    let names = Set(cases.flatMap { $0.node.elements.map { $0.name.text } })
    return variables().storedMembers().filter { variable in
        !variable.node.modifiers.contains { ["static", "class"].contains($0.name.text) }
    }.members(of: model).flatMap { property in
        property.bindingNames.filter { !names.contains($0) }.map { name in
            property.failure(
                message: "Include \(name) in this type's CodingKeys.",
                evidence: ViolationEvidence(
                    observed: "stored property \(name) has no direct CodingKeys case",
                    expectation: "explicit CodingKeys lists every direct stored instance property"
                )
            )
        }
    }
}
```

`codingKeysCoverDirectStoredInstanceProperties` in
[RelatedRuleRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/RelatedRuleRecipeTests.swift)
accepts complete keys, renamed raw values, and automatic synthesis. It excludes
static properties, computed properties, and nested types' members. A case in a
nested helper or another file cannot cover the selected field. Each missing
field produces a failure at its property declaration, with source evidence.

The repair is to add the missing case. Intentional omissions need a narrower
scope or a different project policy. This example checks explicit `Codable`
structs and direct enum cases. It does not combine extensions, resolve property
wrappers, interpret conditional compilation, or analyze custom encoders.

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

When the project changes its API conventions, synchronization boundaries, route
registration, or traversal ownership, revise or remove the corresponding rule and fixtures.
