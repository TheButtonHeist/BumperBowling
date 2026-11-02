# Migrate to the SwiftLint-backed DSL

Version 0.7.0 is a breaking change. Keep using version 0.6.0 if you
need its architecture DSL or other retired features. Do not replace an existing
configuration until its required conventions have passing and failing examples
on the new path.

## Product boundary

Bumper remains a Swift DSL for readable rule authorship and management.
SwiftLintFramework replaces its evaluator, parser ownership, cross-file storage,
and reporting infrastructure. Each named DSL rule maps to one native rule type.
The change does not wrap the old engine inside a SwiftLint rule.

The verified toolchain is Swift 6.4 with SwiftLint 0.63.3 and SwiftSyntax
604.0.0-prerelease-2026-04-21. The old Swift 6.2 minimum no longer applies.

## Move the package first

1. Preserve `BumperBowling.swift` and the old `.bumper` directory outside the new destination.
2. Run `bumper init` in the new destination. Use `--package-path` for a local development checkout.
3. Move rules into named `SyntaxRule` or `RepositoryRule` types.
4. Move fixtures into the generated ordinary test target.
5. Register the types in `Sources/BumperRulesRunner/main.swift`.
6. Run tests and lint before removing the preserved configuration.

Initialization refuses to overwrite either old configuration form. It does not
perform a partial automatic conversion.

## Rule source changes

| Previous API | New direction |
| --- | --- |
| `let rule = Rules.forbid(..., id:summary:)` | Named `SyntaxRule`; static `RuleMetadata`; static builder `body` uses `Rules.forbid` |
| `Rules.each(..., id:summary:)` | The same query/check inside a static `SyntaxRule.body` |
| `Rules.files` / `VisitorRule` | `Rules.files` over the existing tree; ordinary SwiftSyntax visitors |
| `Rules.repository` with `DerivedFact` | static `RepositoryRule.body` with `Rules.repository(scope:collect:)` and typed `FileInfo` |
| `SourceFileContext` parsing initializer | Context supplied by the DSL over SwiftLint’s cached tree |
| `RuleScope.under` / `.files` | Repository-relative scope with the same path intent |
| Component-derived scopes | Explicit source paths or a repository-owned scope predicate |
| `RuleSet` / `Rules { instance }` | `BumperProject { RuleType.self }` |
| Dynamic IDs on several instances of one type | Separate named rule types with stable metadata |
| `RuleReport.violations` | Native `[StyleViolation]` |
| Typed path wrappers in fixtures | Validated repository-relative fixture strings |
| `ViolationMatcher` optional fields | Exact ID, path, line, column, severity, and reason |

`Rules.assert`, the standard shaper catalog, `BuiltInFacts`, `FactProvider`,
`DerivedFact`, and the old visitor adapter are removed. Port useful conventions
through the small syntax and repository surfaces. Do not rebuild unused factory
and fact inventories solely for source compatibility.

The three canonical migrations are executable: matching previews, direct
`CodingKeys` coverage, and cross-file route registration. See
[recipes](RULE_RECIPES.md).

## Builder authoring

Authored rules declare static metadata and bodies. Remove native
`configuration = RuleSettings<Self>()` storage and `init()` from rule types.
Those requirements now belong to private SwiftLint adapters. The repository
root is available as `file.root` in raw callbacks. The old public `BumperRule`
protocol is removed. Custom native rules can conform to `SourceKitFreeRule`
directly.

Low-level `BumperRunner` methods still accept native rule types. For authored
rule types, use the project builder or pass `BumperProject { MyRule.self }.rules`.
The adapters remain internal.

`SyntaxRule.body` is a check builder. Use `Rules.forEach` for per-match builder
bodies and `Rules.require` for Boolean or same-file requirements. Existing
`Rules.each` and `Rules.files` callbacks still return raw failures.

`Rules.repository` keeps its typed collection closure; its check closure now
builds checks. Wrap custom array-producing logic in `Rules.files`, or use a loop
that emits requirements. Do not return raw failure arrays from that builder.

To register several authored types in a fixture harness, use
`RuleTestHarness { FirstRule.self; SecondRule.self }`. Native rule arrays remain
supported. One authored type still has one stable identity; configurable rule
instances are not introduced by this change.

## Architecture features

`Architecture`, `Component`, `ComponentRequirement`, `ComponentShape`,
`AssertionShape`, ownership coverage, dependency graph snapshots, and the old
architecture reports are retired in this product direction. They are not
silently preserved by the new DSL.

Repository import and source ownership conventions have small
[boundary helpers and executable migration recipes](BOUNDARY_MIGRATION.md):
`Rules.importOwnership`, `Rules.forbiddenImports`, and `Rules.sourceOwnership`.
Declaration access, contract types, and bounded same-file alias inspection are
available directly over the existing syntax tree. These are helpers, not the
retired fact-store API. A full architecture consumer still needs an explicit
port and fixtures. Graph configuration and reports are not preserved.

The repository’s parser, process, and declaration-level mutation policies are
ported. Direct parsing is now forbidden everywhere in Bumper source because
SwiftLint owns parsing. Mutation exceptions remain only for `BoundedOutputBuffer`
in `ConfigurationCommandRunner.swift`, `SyntaxNodeCollector` in `SyntaxQuery.swift`,
and native `RuleSettings`, `NativeSyntaxRule`, and `NativeRepositoryRule` in
`RuleDefinition.swift`. New mutable models in those files still fail. The former parser visitor and fact cache no longer exist.

## Diagnostics and failures

Warning and error use SwiftLint’s native severities. `.note` is removed. Native
`StyleViolation.reason` is the diagnostic payload; the old separate
observed/expectation/details JSON schema is removed. Put the repair and required
evidence in the reason. Existing canonical rule IDs remain unchanged.

Predicates are nonthrowing. Configuration and input preflight can throw and fail
the host. A missing repository subject or a DSL diagnostic outside its subject
scope is an infrastructure failure. It does not become a clean report.

Legacy `--format`, `--baseline`, `--fail-on`, `--progress`, and `--timings` options
and `scan`, `snapshot`, `config`, `explain`, and `baseline` commands are removed.
The primary commands are `init`, `test`, and `lint`. More native reporting or
baseline workflow needs a concrete consumer before it becomes Bumper API.

## Execution and cache changes

The ordinary `.bumper` package replaces generated manifests, source copying,
describe/evaluate transport, and the custom build cache. SwiftPM owns build
reuse. `BUMPER_CACHE_DIR` is obsolete. Debug is the default build configuration;
`BUMPER_RUNNER_BUILD_CONFIGURATION=release` still selects release.

The evaluation sandbox remains on `bumper lint`: writes and network are denied.
The environment now contains only `TOOLCHAIN_DIR` so SourceKitten can load the
selected toolchain library without running tool discovery inside the sandbox.
Builds and tests retain normal process access and require trusted code.
Direct `swift run` bypasses the CLI sandbox, as an ordinary executable invocation.

The bounded process helper and its runtime tests remain. Source containment,
symlink, UTF-8, file-count, per-file, and total-byte checks remain. Symlinked
source directories are rejected explicitly. Empty or missing configured source
roots fail clearly. The input-count budget now counts Swift files; the retired
unsupported-language ownership inventory is gone.

SwiftLint’s persisted violation cache is disabled. SwiftPM’s dependency builds
remain cached. Runtime acceptance checks verify rule edits, companion edits,
test failures, native diagnostics, build reuse, and consumption from another
package.

Tests tied to generated-runner cache corruption, old
transport, architecture models, fact store, and legacy evaluator are removed
with their owners. The retained process tests and new source-safety, DSL,
consumer-policy, sandbox, and journey checks protect the new contracts. They do not
claim equivalent coverage for retired features.
