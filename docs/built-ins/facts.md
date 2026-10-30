# Built-In Facts

[Built-ins index](README.md)

Fact providers derive typed repository observations once per evaluation. The
engine memoizes each provider result.

Source observations include unowned files. Their `component` is optional.
Architecture-specific dependency edges require an owned source and a declared
target component. No placeholder component represents an unowned file.

A provider ID identifies the complete derivation, including parameters. The
first result or error for an ID is shared within one run. The cache does not
compare provider values or closure captures.

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
| `BuiltInFacts.effectiveAccess` | Legacy nominal-only access caps. Use declaration contracts for complete signatures and unresolved access. |
| `BuiltInFacts.enclosingDeclarations` | Each declaration's enclosing nominal chain. |
| `BuiltInFacts.memberReferences` | Member-access spelling and optional base spelling. |
| `BuiltInFacts.namedDeclarations` | Public and non-public nominal types, functions, variables, and type aliases with access, attributes, path, component, and location. |
| `BuiltInFacts.declarationContracts` | Explicit declarations, enclosing context, explicit and lexical effective access, and signature types with source locations. |
| `BuiltInFacts.typeReferences` | Explicit function/initializer parameter and return, local-binding, and type-alias type syntax. |
| `BuiltInFacts.componentDependencies` | Component import edges derived from configuration. |

For count requirements, use the cardinality factory:

```swift
Rules.assert(
    structs().filter { $0.node.name.text.hasSuffix("Environment") },
    cardinality: .exactly(1),
    counting: .repository,
    id: "environments.one",
    summary: "One environment struct per counting unit."
)
```

For relationships between observations, request facts inside `Rules.repository`
through `context.facts(_:)`. The [route recipe](../RULE_RECIPES.md#relationships-across-files)
collects declarations and registrations once, then compares them in a scoped rule.

Define another provider by conforming a value type to `FactProvider`. A
provider can read other providers through the same `context.facts(_:)` call.

## Declaration contracts and lexical lookup

`BuiltInFacts.declarationContracts` includes functions, initializers, properties
(stored and computed), subscripts, typealiases, enum cases, nominal types, and
associated types. Each contract carries its path, component, location, enclosing
`LexicalContext`, attributes, and explicit signature types. Each type reference
retains its original `syntax` for custom SwiftSyntax queries and lexical lookup,
as well as its value-only `type` shape. Private and internal
declarations remain available to consumer rules.

`explicitAccess` is nil when no access modifier was written. Setter modifiers
such as `private(set)` do not change the getter's explicit access.
`effectiveAccess` is either `.resolved(AccessLevel)` or `.unresolved(reason)`.
Protocol requirements and enum cases inherit enclosing access. Extension
members inherit an explicit extension default; enclosing types cap access.
Extensions require a unique target declaration in the same file. Implicit
override access remains unresolved. Conditional branches are inventoried as
written; these facts do not identify the active build configuration.

For example, a consumer can check tuples across every exported signature:

```swift
Rules.repository("project.exported_tuples", summary: "Export named types.") { context in
    try context.facts(BuiltInFacts.declarationContracts).flatMap { contract -> [RuleFailure] in
        guard contract.effectiveAccess == .resolved(.public)
            || contract.effectiveAccess == .resolved(.open) else { return [] }
        return contract.types.compactMap { reference in
            guard reference.syntax.descendants(of: TupleTypeSyntax.self)
                .contains(where: { $0.elements.count > 1 }) else { return nil }
            return RuleFailure(path: contract.path, location: reference.location,
                               message: "Export a named type instead of a tuple.")
        }
    }
}
```

This is a consumer policy, not a built-in tuple ban. Policies that require a
complete exported surface must also handle `.unresolved` access explicitly.

`file.declarationContracts()` exposes the same observations inside file rules.
Contracts with the `globalActor` attribute inventory lexical global-actor
declarations; this does not prove that the compiler accepts their definitions.

`LexicalTypeResolver(file:)` follows file-local aliases from a `TypeSyntax` node.
Lookup starts at the nearest lexical scope. `resolve(_:)` returns the final
`TypeShape`, terminal `syntax`, the alias chain, outer function attribute facts,
and an optional failure. It follows optional (`?`, `!`, `Optional<T>`, `Swift.Optional<T>`),
parenthesized, and attributed wrappers. A callback parameter's attributes do
not become attributes of the outer callback.

Alias cycles, ambiguous names, and the default 32-hop limit produce explicit
failures. Unknown names, imported or qualified aliases, inherited aliases,
and generic alias substitutions remain unresolved. A partial shape is not a
resolved type identity. Global actors are identified through same-file
`@globalActor` declarations, including lexical attribute aliases; names ending
in `Actor` have no special meaning. Other attributes retain their spelling and
an unresolved result.

```swift
Rules.each(variables(), id: "project.callback_policy", summary: "Require explicit callback analysis.") { variable in
    let resolver = LexicalTypeResolver(file: variable.file)
    return variable.node.bindings.compactMap { binding in
        guard binding.bumper.identifierName == "onChange",
              let type = binding.typeAnnotation?.type else { return nil }
        let callback = resolver.resolve(type)
        guard callback.failure != nil else { return nil }
        return variable.file.failure(at: type, message: "Callback analysis needs more context.")
    }
}
```

These APIs do not infer types, load other files, or establish compiler symbol
identity. Custom providers, queries, rules, and raw SwiftSyntax remain available.

Next: [Build a rule from the ground up](../RULE_FROM_THE_GROUND_UP.md)
