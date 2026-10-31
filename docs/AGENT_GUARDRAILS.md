# Write useful repository conventions

Start with a repeated review decision that Swift permits. State the scope,
observation, mismatch, and repair. Do not add a rule merely to prohibit syntax.

Read the repository’s `.bumper` package, existing rule tests, and
[authoring guide](RULE_AUTHORING.md). Reuse its queries and vocabulary.

Keep policy in the Swift DSL. Register each named rule explicitly. Reuse parsed
syntax and native cross-file collection. Do not add a parser, generic fact cache,
wrapper engine, or configuration framework for one convention.

Use paired public-harness fixtures. Passing examples must produce zero findings.
Failing examples must assert count, ID, path, location, severity, and message.
Include near misses and legitimate exceptions.

Describe syntax limits honestly. Keep runtime tests for runtime behavior.
Run `bumper test .` and `bumper lint .` before review.
