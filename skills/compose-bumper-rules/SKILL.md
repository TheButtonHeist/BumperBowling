---
name: compose-bumper-rules
description: Author, review, and test repository conventions with Bumper Bowling's Swift DSL over SwiftLintFramework and SwiftSyntax. Use for .bumper packages, SyntaxRule, RepositoryRule, Rules.forbid/each/files/repository, SyntaxQuery, and paired rule fixtures.
---

# Compose Bumper Rules

Make a repeated review convention executable with the smallest clear Swift policy.
Read the repository's `.bumper/Package.swift`, rule source, and tests first.
Read `docs/RULE_AUTHORING.md` and `docs/RULE_RECIPES.md` when available.

## Workflow

1. State the convention, source scope, observation, mismatch, and repair.
2. Reuse existing queries and repository vocabulary.
3. Choose `SyntaxRule` for file checks and `RepositoryRule` for cross-file relationships.
4. Give the type stable `RuleMetadata`, `RuleSettings<Self>`, and a policy body.
5. Use `Rules.forbid`, `Rules.each`, `Rules.files`, or `Rules.repository` as needed.
6. Register the type explicitly in `BumperProject`.
7. Add paired passing and failing examples through `RuleTestHarness`.
8. Run repository tests and lint.

`SyntaxQuery<Node>` accepts any SwiftSyntax node. Use direct-member queries for
member policies, descendant queries for nesting, and same-file queries for
companions. Use ordinary Swift or a visitor when that is clearer.

Reuse `file.syntax` and `file.source`. Never parse source again. A repository
rule collects typed `FileInfo` from every included file through SwiftLint;
its scope selects subjects. Do not add a second evaluator or generic fact cache.

## Proof

Passing fixtures must produce zero findings. Failing fixtures must assert count,
ID, path, line, column, severity, and repair reason. Test near misses and legitimate
exceptions through the same rule type and harness.

These are syntax checks. Do not claim compiler identity, complete alias resolution,
or runtime correctness. Retain runtime tests for runtime behavior.

## Maintenance

Keep each convention small. Revise or remove it when the decision changes.
Export public types from a normal named Swift package to share them. Native
SwiftLint rules can be registered alongside DSL rules.

Run `bumper test .`, `bumper lint .`, and `git diff --check`. This DSL is a breaking
update; read `docs/MIGRATION.md` before replacing an old configuration.
