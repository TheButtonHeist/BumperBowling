# Build An Architecture Rule From The Ground Up

This guide builds one Bumper Bowling rule from the ground up. The rule gives
one subsystem ownership of recursive tree traversal.

This is a specialized example for a project that centralizes tree traversal.
The graph uses call spellings. It does not resolve compiler identity, overloads,
aliases, or dynamic dispatch. Iterative traversal is outside this rule.

The example is useful because every layer is visible. SwiftSyntax supplies
source observations. The repository gives those observations architectural
meaning.

## Start With Valid Swift

The repository defines a recursive value:

```swift
enum Tree {
    case leaf
    case branch([Tree])
}
```

The intended traversal lives in `Sources/TreeTraversal`:

```swift
// Sources/TreeTraversal/Walk.swift

func walk(_ tree: Tree) {
    if case let .branch(children) = tree {
        for child in children { walk(child) }
    }
}
```

A feature later adds another traversal:

```swift
// Sources/Features/Search/Search.swift

func search(_ tree: Tree) {
    if case let .branch(children) = tree {
        for child in children { search(child) }
    }
}
```

Both functions are valid Swift. The repository also requires all `Tree`
traversal to live in `Sources/TreeTraversal`.

## Observe The Source

Bumper Bowling parses each file once with SwiftSyntax. Its `functions()` query
returns typed `FunctionDeclSyntax` matches:

```swift
for match in functions().matches(in: file) {
    let function = match.node
    let name = function.name.text
    let location = file.position(of: function)
}
```

The query does not know what a traversal is. It only exposes Swift syntax.

For each function, Bumper Bowling records facts such as these:

```text
function: search
parameter: tree
parameter type: Tree
local call: search
matched case: branch
matched expression: tree
path: Sources/Features/Search/Search.swift
```

These facts still have no architectural meaning.

## Derive Recursive Call Groups

`BuiltInFacts.recursiveCallGroups` connects locally dispatched function calls.
It finds direct recursion:

```text
walk -> walk
search -> search
```

It also finds mutual recursion:

```text
visit -> descend
descend -> visit
```

A repository rule reads the derived fact through the public fact interface:

```swift
let groups = try context.facts(
    BuiltInFacts.recursiveCallGroups
).groups
```

The returned fact has this public definition:

```swift
public struct RecursiveCallGroups: Sendable {
    public let groups: [[CallGraphFunction]]

    public init(groups: [[CallGraphFunction]]) {
        self.groups = groups
    }
}
```

Each inner array is one strongly connected component of the local call graph.
A one-function group represents direct recursion. A larger group represents
mutual recursion.

Each `CallGraphFunction` retains its parameters, case patterns, path,
component, and source location:

```swift
public struct CallGraphFunction: Hashable, Sendable {
    public let function: FunctionSymbol
    public let enclosingType: NominalSymbol?
    public let parameters: [CallGraphParameterEvidence]
    public let casePatterns: [CasePatternEvidence]
    public let path: RelativeFilePath
    public let component: ComponentID?
    public let location: SourcePosition?
}
```

The provider performs this transformation:

```text
FunctionDeclSyntax
    -> CallGraphFunction
    -> locally dispatched call edges
    -> strongly connected components
    -> RecursiveCallGroups
```

## Give The Facts Meaning

This repository defines a `Tree` traversal with four conditions:

- The functions form a recursive call group.
- A function has a parameter spelled `Tree`.
- The function matches `.branch` against that parameter.
- The implementation is outside `Sources/TreeTraversal`.

The following rule expresses that definition. The code is expanded to show
the composition.

```swift
let treeTraversalRule = Rules.repository(
    "architecture.tree_traversal",
    summary: "Tree traversal belongs to TreeTraversal."
) { context in
    let owner = RuleScope.under("Sources/TreeTraversal")
    let groups = try context.facts(
        BuiltInFacts.recursiveCallGroups
    ).groups

    return groups.flatMap { group in
        let traversesTree = group.contains { function in
            let treeParameters = Set(
                function.parameters
                    .filter { $0.typeSpelling == "Tree" }
                    .map(\.localName)
            )

            return function.casePatterns.contains {
                $0.memberName == "branch"
                    && treeParameters.contains($0.subjectExpression)
            }
        }

        guard traversesTree else {
            return []
        }

        return group
            .filter {
                !owner.includes(
                    SourceFileDescriptor(
                        path: $0.path,
                        component: $0.component
                    )
                )
            }
            .map {
                RuleFailure(
                    path: $0.path,
                    location: $0.location,
                    message: "Tree traversal belongs to TreeTraversal."
                )
            }
    }
}
```

`Tree`, `branch`, and `Sources/TreeTraversal` come from the repository. Bumper
Bowling supplies syntax queries, facts, scopes, rule evaluation, and reports.

## Apply The Rule

Add the rule to the project configuration:

```swift
let bumper = BumperProject {
    Included {
        "Sources"
    }

    Rules {
        treeTraversalRule
    }
}
```

The invalid `search` function now produces a source-based failure:

```text
Sources/Features/Search/Search.swift:3
Tree traversal belongs to TreeTraversal.
```

The rule, tests, CLI, CI job, and agents all use the same result.

## Use The Shipped Composition

Bumper Bowling packages this composition as `Rules.canonicalTraversal`:

```swift
Rules {
    Rules.canonicalTraversal(
        root: "Tree",
        structuralCase: "branch",
        owners: .under("Sources/TreeTraversal")
    )
}
```

The short form uses the same fact provider and rule engine as the expanded
form. It is a convenience built from public Bumper Bowling pieces.

A repository can use the short form, write another fact-based rule, or start
from a raw `SyntaxQuery` or `SyntaxVisitor`.

## The Composition

```text
SwiftSyntax nodes
    -> source observations
    -> recursive call groups
    -> repository meaning
    -> reusable rule
    -> applied policy
    -> source evidence
```

SwiftSyntax describes the code. The repository defines the rule. Bumper
Bowling connects the two and reports where the code breaks the rule.
