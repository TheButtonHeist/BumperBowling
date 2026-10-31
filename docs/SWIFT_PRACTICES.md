# Swift Practices Behind the Examples

These examples start with published Swift guidance. Each example then states a
project decision that Bumper Bowling can check from syntax and repository context.
The project decision can be stricter than the source guidance.

| Practice | Primary source | Example policy |
| --- | --- | --- |
| Give mutating and nonmutating counterparts consistent names. | [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/#strive-for-fluent-usage) | Selected value types that declare `formUnion(_:)` also declare a matching `union(_:) -> Self`. |
| Make time, identifiers, and other external dependencies controllable in tests. | [Point-Free's dependency examples](https://github.com/pointfreeco/swift-dependencies) | Construct `ContinuousClock` only in the project's dependency adapters. Other code receives a clock. |
| Use unchecked concurrency conformances deliberately around manual synchronization. | [Swift concurrency migration guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/#Manual-Synchronization) | Written `@unchecked Sendable` conformances belong in the project's synchronization adapters. |
| Keep public interfaces intentional. | [Swift access control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/) | Public and SPI declarations stay inside selected API surfaces. |
| Declare dependencies between modules. | [SwiftPM target dependencies](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#target-dependencies) | Observed imports also obey the project's narrower component boundaries. |

The first three policies have complete public-harness examples in
[SwiftPracticeRecipeTests.swift](../Tests/BumperBowlingTestSupportTests/SwiftPracticeRecipeTests.swift).
The public-surface fixtures are in
[RuleSurfaceCoverageTests.swift](../Tests/BumperBowlingTestSupportTests/RuleSurfaceCoverageTests.swift).
The [rule recipes](RULE_RECIPES.md) explain the rules, repairs, and limits.

## What the compiler accepts

A value type can expose only an in-place operation. A library function can
construct its own clock. A manually synchronized class can declare unchecked
sendability outside the team's chosen adapter directory. All are valid Swift.
Bumper checks the additional project policy.

Tests include these cases and similar code that must remain allowed. A method
in another type cannot supply a missing counterpart. Receiving a clock does
not construct one. A checked `Sendable` conformance needs no exemption.

## What belongs elsewhere

The compiler checks types and actor isolation. Runtime tests check synchronization,
clock behavior, and operation semantics. Syntax checks do not replace either.

API clarity still requires review. Formatting and existing local style checks
belong in the formatter or SwiftLint. The examples focus on relationships,
selection, and exceptions that require the project's context.

Optionals, booleans, existentials, loops, and mutation all have legitimate uses.
These examples impose no blanket bans on them. SwiftUI previews, registries,
and centralized traversal remain optional project conventions.

The core examples use library values, clocks, and synchronization adapters.
Framework-specific recipes state their context. Names and scopes describe each
example's explicit contract.
