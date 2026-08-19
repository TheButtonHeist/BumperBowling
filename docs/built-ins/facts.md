# Built-In Facts

[Built-ins index](README.md)

Fact providers derive typed repository observations once per evaluation. The
engine memoizes each provider result.

| Fact | Value |
| --- | --- |
| `BuiltInFacts.sourceFiles` | Projected facts for each source file. |
| `BuiltInFacts.imports` | Import occurrences with module, path, and component. |
| `BuiltInFacts.declarations` | Nominal declaration occurrences and symbol lookup. |
| `BuiltInFacts.nominalTypes` | Nominal kind, access, inheritance, path, and location. |
| `BuiltInFacts.extensions` | Extension declarations and extended type spellings. |
| `BuiltInFacts.storedProperties` | Stored-property type, mutability, owner, path, and location. |
| `BuiltInFacts.syntaxNodes` | Observed syntax-node kind, spelling, parent, and ancestors. |
| `BuiltInFacts.functionCalls` | Function and initializer call spellings and locations. |
| `BuiltInFacts.directRecursion` | Functions that call themselves through local dispatch. |
| `BuiltInFacts.recursiveCallGroups` | Direct and mutual recursive call groups. |
| `BuiltInFacts.effectiveAccess` | Declared and effective access levels. |
| `BuiltInFacts.enclosingDeclarations` | Each declaration's enclosing nominal chain. |
| `BuiltInFacts.memberReferences` | Member-access spelling and optional base spelling. |
| `BuiltInFacts.namedDeclarations` | Public and non-public nominal types, functions, variables, and type aliases with access, attributes, path, component, and location. |
| `BuiltInFacts.typeReferences` | Explicit function/initializer parameter and return, local-binding, and type-alias type syntax. |
| `BuiltInFacts.componentDependencies` | Component import edges derived from configuration. |

Read a fact inside `Rules.repository`:

```swift
Rules.repository(
    "project.one_environment",
    summary: "AppEnvironment has one declaration."
) { context in
    let declarations = try context.facts(
        BuiltInFacts.declarations
    )

    return declarations.occurrences(of: "AppEnvironment").count == 1
        ? []
        : [
            RuleFailure(
                path: "Sources/Application/AppEnvironment.swift",
                message: "AppEnvironment does not have one declaration."
            )
        ]
}
```

Define another provider by conforming a value type to `FactProvider`. A
provider can read other providers through the same `context.facts(_:)` call.

Next: [Build a rule from the ground up](../RULE_FROM_THE_GROUND_UP.md)
