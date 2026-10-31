---
name: compose-bumper-rules
description: Create, review, refactor, and test Bumper Bowling architecture policy. Use when working with BumperBowling.swift, .bumper/Sources, ComponentRequirement, ComponentShape, standard Rules shapers, FactProvider rules, SyntaxQuery rules, per-file rules, or SwiftSyntax visitors.
---

# Compose Bumper Rules

Codify the repository's architecture with the smallest public pieces that
express it. Keep developers, reviewers, CI, and agents on the same policy.

Read `references/bumper-vocabulary.md` before choosing an authoring level. Read
`references/shape-examples.md` when composing repository vocabulary or tests.

When the repository includes Bumper Bowling documentation, use
`docs/built-ins/README.md` for the built-in catalog and `docs/RULE_AUTHORING.md`
for the complete authoring contract.

## Composition Model

Build policy through these visible paths:

```text
SourceFactRule -> ComponentRequirement -> ComponentShape -> Component
RuleConfiguration -> AssertionShape -> Rules block
SyntaxQuery -> Rules.each / Rules.assert / Rules.forbid / Rules.files
FactProvider -> Rules.repository
RuleDefinition -> RuleSet -> Rules block
```

Apply every value explicitly. Use `Applies(.shape)` inside a component. Add
`AssertionShape`, `RuleSet`, and `RuleDefinition` values inside `Rules { ... }`.
Importing Swift code only makes values available.

## Authoring Ladder

Choose the first level that honestly expresses the invariant:

1. **Architecture DSL and composition**: declare components, ownership,
   dependencies, capabilities, and source requirements. Combine source facts
   into `ComponentRequirement`. Combine component elements into
   `ComponentShape`. Combine graph assertions into `AssertionShape`.
2. **Standard shapers**: prefer an existing `Rules.*` factory such as
   `Rules.singleDeclaration`, `Rules.constructionOwnership`,
   `Rules.importOwnership`, `Rules.memberReferenceOwnership`, or
   `Rules.canonicalTraversal`.
3. **Typed facts**: use `Rules.repository(...)` and request memoized providers
   with `context.facts(...)`. Reuse `BuiltInFacts` before defining a new
   `FactProvider`. Let custom providers request other providers.
4. **Typed queries and per-file rules**: compose `SyntaxQuery` roots, file
   scopes, lexical scopes, and typed views. Use
   `Rules.each(...)`, `Rules.assert(...)`, `Rules.forbid(...)`, or `Rules.files(...)` when typed
   facts are insufficient but parsed syntax is enough.
5. **Raw visitor**: use `Rules.visitor(...)` / `VisitorRule` with a real
   SwiftSyntax `SyntaxVisitor` only when typed queries cannot express the walk.
   Keep failure collection in the visitor.

The repository's `docs/RULE_RECIPES.md` progression demonstrates
increasing complexity through paired public-harness fixtures. For model shape,
select declarations and inspect direct members. File layout must not stand in
for the declaration that the policy governs. Document the exact matching unit.

## Workflow

1. Read `BumperBowling.swift`, `.bumper/Sources`, and `.bumper/Package.swift`.
2. Read the repository's rule catalog and existing rule tests.
3. State the invariant as `observed source fact + declared scope = mismatch`.
4. Name the expected evidence and the repair before writing code.
5. Search existing requirements, shapes, rule IDs, shapers, providers, queries,
   and visitors.
6. Choose the narrowest honest scope and the highest viable authoring level.
7. Put one-off vocabulary inline, repository-owned reusable code in
   `.bumper/Sources`, and genuinely cross-repo vocabulary in a local
   `.bumper/Package.swift` product named `BumperRules`.
8. Apply the value explicitly in `BumperBowling.swift`.
9. Add positive and mutation tests.
10. Update the rule catalog with rationale, scope, repair, proof, and deletion
    condition.

When the architecture changes, update the source, policy, fixtures, and catalog
in the same change.

## Composition Practices

- Build small requirements, shapes, queries, and fact providers.
- Name their compositions with repository language such as `.feature`,
  `.parser`, or `.valueModel`.
- Make nesting visible with `Applies`, `ComponentRequirement(...)`, and
  `RuleSet { ... }`.
- Reuse the engine's parsed syntax and memoized facts. Do not parse files again
  inside a rule.
- Keep strings at configuration boundaries. Use typed symbols, paths, scopes,
  facts, and syntax nodes in rule logic.
- Keep one evaluator. Built-in and project rules belong in the same `Rules`
  block and produce the same report.

## Rule Contract

Give every project rule:

- A stable, specific rule ID
- A `summary` that states the expected invariant
- The narrowest honest `RuleScope`
- A source location when SwiftSyntax provides one
- Evidence that names the observation and expectation
- A repair that a developer or agent can perform

Let analysis errors fail the run. Never translate a failed derivation into an
empty match set.

## Sustainability Gate

Before adding or retaining a rule:

1. Reject historical spellings and compatibility aliases.
2. Reject states already rejected by the Swift compiler.
3. Delete rules for states that architecture or types made unconstructible.
4. For a rule below the standard-shaper level, audit an existing rule at that
   level or lower. Reuse its fact or query when possible.
5. Record why the next higher level cannot express the invariant.

## Test Contract

Every project-defined `Rules.repository`, `Rules.files`, or visitor rule needs
both tests through `RuleTestHarness` with arrays of `SourceInput`:

- **Positive test**: a valid fixture produces no violations.
- **Mutation test**: minimally mutate that valid fixture into the forbidden
  state and assert the exact rule ID, path, message, available location, and
  evidence that the rule promises.

The rule's metadata summary explains a violation at runtime. The catalog
explains why the project owns the rule and when to delete it. Both are required.
Tests do not substitute for either.

## Validation

Run the smallest focused rule tests first, then validate the consumer surface:

1. `swift run bumper config .`
2. Focused `RuleTestHarness` positive and mutation tests
3. `swift run bumper test .`
4. `swift run bumper lint . --timings`
5. `git diff --check`

Do not raise evaluation timeouts to hide a slow rule. Read the rule and fact
provider timings, reuse an existing fact, and remove repeated parsing or
quadratic accumulation before changing the execution budget.

## References

- Read `references/bumper-vocabulary.md` for current public spellings.
- Read `references/shape-examples.md` for placement and test examples.
