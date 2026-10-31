# Public DSL

The language is ordinary Swift. It does not have a separate parser or runtime.

| Surface | Purpose |
| --- | --- |
| `BumperProject(included:excluded:) { Rule.self }` | Select source roots and register distinct rule types |
| `SyntaxRule` | A native SwiftLint rule whose body checks one file |
| `RepositoryRule` | A native collecting rule whose body compares typed file observations |
| `RuleMetadata(id:summary:severity:)` | Stable identity, explanation, and warning/error severity |
| `RuleSettings<Self>` | Native configuration carrying the repository root |
| `Rules.forbid(pattern, scope:)` | Report each forbidden match with a repair message |
| `Rules.each(pattern, scope:)` | Return located failures from each selected match |
| `Rules.files(scope:)` | Use arbitrary Swift or a visitor over one parsed file |
| `Rules.repository(scope:collect:)` | Collect all included files, then check scoped subjects |
| `RuleScope` | An open file predicate with path conveniences |
| `SyntaxQuery<Node>` / `SyntaxPattern` | Typed, composable SwiftSyntax matching |
| `SyntaxMatch.failure(message:)` | Construct a finding at a matched node |
| `RuleTestHarness` / `ViolationMatcher` | Evaluate paired examples and assert exact native findings |

The project builder supports conditions and loops. Importing a rule package
does not register its rules. Registration is explicit and duplicate IDs fail.

A rule type has one static identity. Policies are Swift source; YAML and dynamic
closure-to-type translation are not part of the Bumper DSL.

See [authoring](RULE_AUTHORING.md) for composition and [migration](MIGRATION.md)
for retired APIs.
