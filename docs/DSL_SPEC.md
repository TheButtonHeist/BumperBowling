# Public DSL

Bumper builds repository conventions from Swift values. SwiftLint hosts each
rule; SwiftSyntax supplies the typed source tree.

| Surface | Purpose |
| --- | --- |
| `BumperProject(included:excluded:) { Rule.self }` | Select source roots and register rule types |
| `SyntaxRule` | Declare static metadata and a check-builder body for one file |
| `RepositoryRule` | Declare metadata, typed `FileInfo`, and a repository body |
| `RuleMetadata(id:summary:severity:)` | Stable identity, explanation, and warning/error severity |
| `CheckBuilder` | Combine checks, reusable fragments, conditions, and loops |
| `Rules.forEach(pattern, scope:) { match in ... }` | Build checks for each selected syntax match |
| `Rules.require(condition, at:message:)` | Report at a match when a Boolean condition is false |
| `Rules.require(inSameFile:at:message:)` | Require at least one companion from the anchor's file and syntax tree |
| `Rules.forbid(pattern, scope:)` | Report each forbidden match with a repair message |
| `Rules.each(pattern, scope:)` | Return raw located failures from each selected match |
| `Rules.files(scope:)` | Use arbitrary Swift or a visitor over one parsed file |
| `Rules.repository(scope:collect:check:)` | Collect typed observations, then build checks for scoped subjects |
| `RuleScope` | A file predicate with repository-relative path conveniences |
| `SyntaxQuery<Node>` / `SyntaxPattern` | Typed, composable SwiftSyntax matching |
| `SyntaxMatch.failure(message:)` | Construct a finding at a matched node |
| `RuleTestHarness` / `ViolationMatcher` | Evaluate examples and assert exact native findings |

## Builder semantics

Every applicable sibling check executes. Findings accumulate; a failure does
not short-circuit later checks. Empty blocks and unselected branches contribute
no findings. Conditions, optional bindings, switches, loops, and local constants
use Swift's result-builder syntax. Early return, `guard`, and throwing algorithms
belong in ordinary helper functions or raw callbacks.

A helper returns `SyntaxCheck`. Add `@CheckBuilder` to the helper when it combines
several checks. Rule bodies, `Rules.forEach` closures, and repository validation
closures infer the builder; authors do not write that attribute there.

A requirement emits one failure at its explicit anchor when unmet. The anchor
sets the diagnostic location; it does not filter away a failure from another
file. The runner rejects findings outside the rule scope. Same-file
requirements mean at least one match, not exactly one. Use Swift counts or sets
for other relationships. Direct-member queries exclude nested declarations;
`matches(within:)` selects strict descendants.

Put the subject scope on the outer `Rules.forEach`, raw file check, or repository
check. The outer check structure validates literal scope paths before execution,
even when a query has no matches. A per-match callback creates its check values
only after that match exists; it cannot declare preflight scope for absent matches.
Sibling checks keep their own selection scopes. Their union bounds the rule's
diagnostics. There is no implicit inherited scope or implicit current match.

## Rule identity and execution

Each author type maps to a private generic native adapter. Authors do not store
native configuration or provide an initializer. Repository root identity is
available as `file.root` inside callbacks. Each adapter specialization retains a
separate SwiftLint identifier and collection slot.

One type has one static identity. Rule instances with independent options are
not supported. Importing a package does not register its rules. Registration is
explicit; duplicate IDs fail. Direct native `SourceKitFreeRule` types can appear
in the same project builder.

The runner collects all files before checking repository subjects. Each
repository rule owns its typed observations. No generic fact store or second
scheduler sits behind the builder. Diagnostics remain native SwiftLint findings.

See [authoring](RULE_AUTHORING.md) for composition and [migration](MIGRATION.md)
for retired APIs. These are syntax checks, not compiler identity analysis.
