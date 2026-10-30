# Placement And Test Examples

## Contents

- [Repo-Owned Vocabulary](#repo-owned-vocabulary)
- [Positive And Mutation Tests](#positive-and-mutation-tests)
- [Review Record](#review-record)

## Repo-Owned Vocabulary

Put reusable policy for one repository under `.bumper/Sources`:

```text
.bumper/
  Sources/
    ArchitectureVocabulary.swift
    ProjectRules.swift
BumperBowling.swift
```

```swift
// .bumper/Sources/ArchitectureVocabulary.swift
import BumperBowlingCore

extension ComponentRequirement {
    static let domainCore = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}

extension ComponentShape {
    static let foundationOnly = ComponentShape {
        MayUse(.foundation)
        DoesNotUse(.uiKit, .testing)
    }

    static let domain = ComponentShape {
        Applies(.foundationOnly)
        Requires(.domainCore, severity: .error)
    }
}

extension AssertionShape {
    static let projectGraph = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

Apply all vocabulary explicitly from `BumperBowling.swift`:

```swift
let bumper = BumperProject {
    Architecture(AppComponent.self) {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
            Applies(.domain)
        }
    }

    Rules {
        ApplyAssertions(.projectGraph)
        projectRules
    }
}
```

`ComponentShape` groups ordinary component elements. `Applies(.domain)` adds
those elements to the current component. The current component's `Owns(...)`
paths set the default scope for its requirements.

A shape can apply another shape. A shape does not create a component, load
rules by convention, or add a second evaluator.

Use inline values for one-off policy. Use `.bumper/Package.swift` only when the
vocabulary is shared across repositories. It must expose a `BumperRules`
library product. A package that names AST types declares its own SwiftSyntax
dependency. Importing the product does not apply any rules.

## Positive And Mutation Tests

Every project-defined closure, query, or visitor rule starts with a valid
fixture. The mutation test changes only the source fact the rule forbids.

```swift
import BumperBowlingCore
import BumperBowlingTestSupport
import SwiftSyntax
import Testing

private let rawInputBoundary = Rules.files(
    "project.repository_input_boundary",
    summary: "RepositoryInput is admitted only at the process boundary."
) { file in
    functions()
        .taking(NominalSymbol("RepositoryInput"))
        .excluding(.under("Sources/Boundary"))
        .matches(in: file)
        .map { match in
            match.failure(
                message: "RepositoryInput belongs at the process boundary.",
                evidence: ViolationEvidence(
                    observed: "RepositoryInput parameter",
                    expectation: "boundary-owned signature"
                )
            )
        }
}

@Test
func acceptsOrdinaryApplicationInput() throws {
    let report = try RuleTestHarness(rawInputBoundary).evaluate(
        [
            SourceInput.swift(
                "Sources/App/Handler.swift",
                component: "app",
                source: "func handle(_ input: Int) {}"
            ),
        ]
    )

    #expect(report.violations.isEmpty)
}

@Test
func flagsRepositoryInputMutation() throws {
    let report = try RuleTestHarness(rawInputBoundary).evaluate(
        [
            SourceInput.swift(
                "Sources/App/Handler.swift",
                component: "app",
                source: "func handle(_ input: RepositoryInput) {}"
            ),
        ]
    )

    let violation = try #require(report.violations.first)
    #expect(report.violations.count == 1)
    #expect(violation.rule.id == RuleID("project.repository_input_boundary"))
    #expect(violation.path.rawValue == "Sources/App/Handler.swift")
    #expect(violation.location != nil)
    #expect(violation.message == "RepositoryInput belongs at the process boundary.")
    #expect(
        violation.evidence == ViolationEvidence(
            observed: "RepositoryInput parameter",
            expectation: "boundary-owned signature"
        )
    )
}
```

Keep the mutation minimal so a passing test proves the intended predicate, not
an incidental difference between fixtures.

## Review Record

For every new rule below the standard-shaper rung, include this information in
the change summary:

```text
Invariant: <observed fact + scope = mismatch>
Runtime summary: <specific sentence shown with violations>
Catalog entry: <rationale, scope, repair, proof, and deletion condition>
Highest viable rung: <typed facts | typed query/per-file | raw visitor>
Higher rung rejected because: <specific missing fact or traversal>
Existing lower-level rule audited: <rule ID or none exists>
Audit outcome: <deleted | promoted | consolidated | retained with reason>
Deletion test: <not historical, not compiler-enforced, still constructible>
Tests: <positive fixture and minimal mutation fixture>
```
