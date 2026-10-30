# Changelog

## Unreleased

### Breaking

- Removed `Rules.canonicalConstruction`. Use `Rules.constructionOwnership` with
  `allowed:`. Existing baselines can retain `id: "canonical_construction"`.
  Repository-specific IDs remain unchanged.
- Removed `Rules.singleNominalSpelling`. The
  [nominal-name recipe](docs/RULE_RECIPES.md#an-explicit-nominal-name-query)
  preserves its nominal-only selection through `Rules.forbid` and a query.
  `Rules.declarationOwnership` also matches functions and variables, so it is
  not an exact replacement.
- Removed the file-based `Rules.maximumStoredProperties` and
  `Rules.stateMachineShape` factories. Use `Rules.each` with selected declarations
  and explicit member or case predicates. The
  [per-declaration recipe](docs/RULE_RECIPES.md#3-requirements-inside-each-declaration)
  demonstrates both missing and excess direct members without a file-layout
  assumption.

- `TypeReferenceOccurrence.Kind` includes member bindings, subscript parameters
  and returns, enum payloads, and associated-type defaults. Exhaustive switches
  must account for these cases.

### Fixed

- Public API ownership now includes initializers, subscripts, and default public
  members in extensions. The named inventory reuses declaration contracts and
  their lexical access defaults. It remains a syntax inventory, not a compiler
  visibility proof.
- Disallowed type references now include member annotations, subscript
  signatures, enum payloads, and associated-type defaults. Findings point to the
  explicit type syntax. Existing declaration contracts supply these facts.

### Added

- A tested progression from a built-in boundary to arbitrary syntax,
  per-declaration requirements, repository counts, shared facts, and a call
  graph. Paired fixtures include scope boundaries and plausible near misses.
- `DeclarationContract.declaredAccess` exposes explicit access or lexical
  defaults independently of unresolved effective access.

### Removed

- Dead public API with no callers or documentation, found by audit:
  `SwiftFileSummary` (`SwiftFileParser.parse(_:)` now returns the same
  `SourceFileFacts` the scanner produces), `SwiftSyntaxNodeCatalog.adding(_:)`,
  `BumperSyntaxView.isA(_:)`/`hasAncestor(_:)`/`isImmutableBinding`,
  `FunctionCallQuery.calleeBaseName`, `ImportInventory.imports(of:)`,
  `RecursiveCallGroups.functions`, `PropertySymbol`, and the
  `ComponentRequirement` `combined(with:)`/`all(_:)`/`+` combinators (use the
  variadic initializer).

## 0.6.0 - 2026-07-15

### Breaking

- `Rules.repository`, `Rules.files`, and `Rules.visitor` now require an
  explicit `summary:`. Project-defined rules can no longer compile with a
  generic runtime explanation.
- `CallGraphFunction.parameterTypeNames` and its matching initializer argument
  were replaced by `parameters: [CallGraphParameterEvidence]` and the required
  `casePatterns: [CasePatternEvidence]`, preserving the subject evidence needed
  for honest traversal checks.

### Changed

- The rule-authoring guide and Codex skill now require the highest viable
  authoring rung, a positive and mutation test, and a consumer-owned catalog
  entry recording rationale, repair, proof, and deletion condition.
- SwiftLint now has a zero-warning strict baseline. Its checked-in contract
  excludes punctuation and size metrics, retains correctness/API hygiene
  rules, and CI promotes every enabled warning to a failure.
- Configuration and consumer-test caches now validate their generated files
  byte-for-byte and rebuild missing or stale executables. Source-mode consumer
  tests use stable fixture roots and an interprocess lock, so SwiftPM can reuse
  compiled work without concurrent runs replacing each other's test target.
- `Rules.canonicalTraversal` now accepts structural case evidence only when the
  case subject is an exact root-typed parameter or `self`. Unrelated enum case
  patterns no longer make a recursive function look like a root traversal.
- The SwiftSyntax dependency accepts both the 602 and 603 release lines, so
  adding Bumper Bowling does not downgrade consumers already using SwiftSyntax
  603.

### Added

- `bumper test`, which runs repository-owned rule tests through ordinary
  SwiftPM discovery. Source-mode repositories can place tests under
  `.bumper/Tests`; package-mode repositories retain their own test-target paths
  and `@testable` visibility.
- Generic syntax evidence for consumer rules: `SyntaxScope`, `LexicalContext`,
  `TypeShape`, qualified type references, outer function attributes, and
  subject-aware case-pattern evidence.
- `Rules.importOwnership` and `Rules.memberReferenceOwnership`, reusable
  shapers for expressing component ownership without embedding a consumer's
  architecture in Bumper Bowling.

## 0.5.2 - 2026-07-14

Large valid projects no longer time out during rule evaluation
([#41](https://github.com/RoyalPineapple/BumperBowling/issues/41)).

### Fixed

- Source-file fact derivation was accidentally quadratic: every syntax node
  re-rendered its whole subtree to produce its spelling
  (`trimmedDescription`), and the per-file syntax catalog copied its full
  `Set` for each node it added. Spellings are now sliced directly from the
  original source bytes and the catalog is built with in-place insertion.
  Evaluation of a representative 300-file repository drops from over 60
  seconds (timeout) to seconds.

### Changed

- The cached `BumperProjectRunner` builds in release configuration and is
  resolved from the matching release path. The runner is a cached artifact,
  so the one-time optimized build cost is paid once per configuration
  change. Cache identity records the build configuration; existing caches
  rebuild once.
- The runner build budget rose from 300 to 600 seconds to cover optimized
  cold builds on slow CI hosts. The evaluation default stays 60 seconds.
- `ConfigurationLoader.evaluateRules(root:input:)` is now
  `evaluateRun(root:input:)` and returns `EvaluationRun` (the canonical
  `RuleReport` plus its telemetry). `RuleReport` itself is unchanged.

### Added

- `BUMPER_EVALUATION_TIMEOUT_SECONDS`: a documented override for the
  evaluation budget, validated at the process boundary. It accepts positive,
  finite seconds; zero, negative, non-numeric, NaN, or infinite values fail
  with `BumperError.invalidEvaluationTimeout`. Evaluation is always bounded.
- `BUMPER_RUNNER_BUILD_CONFIGURATION`: a documented override for the runner
  build configuration on hosts where cold optimized builds are too
  expensive (small CI runners). Only `release` and `debug` are accepted;
  anything else fails with `BumperError.invalidRunnerBuildConfiguration`.
  Cache identity records the configuration.
- Evaluation telemetry for rule authors: `RuleSet.evaluationRun(...)`,
  `BumperProject.evaluationRun(_:)`, and `EvaluationTelemetry` report
  per-rule and per-fact-provider durations. `bumper lint --timings` prints
  host phase timings (prepare, scan, evaluate) and the slowest rules and
  facts to stderr.

## 0.5.1 - 2026-07-14

Closes the remaining letter-of-spec gaps from the open shaper architecture
spec. The spec's example spellings now compile verbatim, enforced by
`SpecSpellingTests`.

### Changed

- Shaper factories use the spec's argument labels: `singleDeclaration(_:owner:)`,
  `constructionOwnership(_:allowed:)`, `boundaryOnly(function:allowed:)`,
  `noAlternateAliases(_:allowing:)`, and `canonicalConstruction(_:owners:)`
  (previously `symbol:`-labeled).

### Added

- `StringMatcher.regex(_:)`: explicit regular-expression matching, validated at
  construction; string literals remain exact matches.
- `RelativeFilePath` and `RelativePathPrefix` are `ExpressibleByStringLiteral`
  at the authoring boundary; a malformed literal is a loud configuration error,
  and runtime strings still use the throwing initializers.
- `BumperProject.scanConfiguration`: the typed `ScanConfiguration` projection
  (included and excluded paths) the host scanner honors.
- `ViolationMatcher` in `BumperBowlingTestSupport`: pure, framework-neutral
  violation predicates with `RuleReport.violations(matching:)` and
  `RuleReport.contains(_:)`.

## 0.5.0 - 2026-07-14

One open rule engine and one project entry point. See
[docs/MIGRATION_0.5.md](docs/MIGRATION_0.5.md) for every removed symbol and its
exact replacement. There are no compatibility aliases.

### Breaking

- `BumperBowling.swift` now declares `let bumper = BumperProject { ... }`
  instead of `let configuration = BumperConfiguration { ... }`, and the
  repository rule block is `Rules { ... }` instead of `Assertions { ... }`.
- Removed the custom rule worker and its surface: `CustomRules()`,
  `CustomRuleSet`, `CustomRule`, `CustomSyntaxRule`, `CustomRuleFailure`,
  `CustomRuleInput`, `CustomRuleOutput`, `CustomRuleFinding`,
  `CustomRuleFileFacts`, `CustomRuleContext`, and
  `CustomRuleWorkerConfiguration`. Project rules are ordinary `RuleDefinition`
  values (`Rules.repository(...)`, `Rules.files(...)`) added to the project's
  `Rules { ... }` block and evaluated by the same engine as built-ins.
- Removed the closed built-in reporting surface: `ArchitectureLinter`,
  `LintReport`, `ArchitectureViolation`, `RuleRegistry`, and
  `RuleDescription`. Built-in rules evaluate as `RuleDefinition`s and every
  interface — CLI, JSON, Markdown, baselines, tests — projects one
  `RuleReport` of `RuleViolation` values.
- Replaced the two cached executables (configuration runner and custom rule
  worker) with one cached `BumperProjectRunner` running in a deny-default
  sandbox with two modes: `describe` emits the architecture configuration;
  `evaluate` reads scanned sources as `RepositoryInput` on stdin, parses each
  file exactly once, and emits one `RuleReport`. Existing caches rebuild once.
- Removed `RuleSet.evaluateConcurrently(...)`; evaluation is sequential in
  declaration order, and reports are sorted deterministically by path, line,
  column, rule ID, then message.

### Added

- Added `BumperProject`, the one authored entry point, with
  `evaluate(_: RepositoryInput) -> RuleReport` for direct use in tests.
- Added typed component keys: `Architecture(MyComponentKey.self) { ... }`
  accepts a project-owned `ComponentKey` enum so `Component(.core)` and
  `MayDependOn(.core)` are compiler-checked. Duplicate normalized component
  IDs are a configuration error.
- Added `RepositoryInput`/`SourceInput`: the host scans raw sources and the
  runner owns all parsing, so each file is parsed exactly once per run.
- Added built-in fact providers `BuiltInFacts.nominalTypes`, `extensions`,
  `storedProperties`, `syntaxNodes`, `effectiveAccess`,
  `enclosingDeclarations`, `memberReferences`, `componentDependencies`, and
  `recursiveCallGroups` (strongly connected components of the locally
  dispatched call graph), joining `sourceFiles`, `imports`, `declarations`,
  `functionCalls`, and `directRecursion`.
- Added shapers `Rules.canonicalConstruction` and
  `Rules.singleNominalSpelling`; upgraded `Rules.canonicalTraversal` to detect
  mutual recursion through call-graph SCCs while ignoring calls on another
  receiver.
- Added duplicate rule ID validation across built-in and project rules.
- Per-family built-in rules now report one stable rule ID with per-setting
  severities folded into each violation.

## 0.4.0 - 2026-07-10

### Breaking

- Renamed the public architecture model from subsystem terminology to component
  terminology so it matches the DSL and documentation. This changes public
  source names and Codable field names such as `subsystems`,
  `SubsystemConfiguration`, `SubsystemID`, and `subsystemBoundary` to their
  component equivalents.
- Added generic syntax-node predicates over SwiftSyntax `SyntaxKind`, spelling,
  parent kind, and ancestor kind so repositories can enforce their own syntax
  policy without Bumper Bowling shipping repo-specific rule taxonomy.

### Added

- Added JSON output for `bumper lint` and `bumper scan` with `--format json`.
- Added `bumper lint --fail-on none|note|warning|error` for advisory CI rollout.
- Added `bumper baseline create` and `bumper lint --baseline` for incremental
  adoption in repos with existing architecture violations.
- Added `bumper lint --progress` and `bumper scan --progress` for large-repo
  visibility.
- Added `BUMPER_CACHE_DIR` so CI can control where compiled configuration
  runners are cached.

### Fixed

- Fixed generated configuration-runner manifests to use an explicit
  `BumperBowling` package identity, so path-based checkouts work even when the
  checkout directory has a different name.
- Fixed composed rule settings so shapes preserve each scoped path, exclusion,
  and severity instead of collapsing compatible rule families into one merged
  setting before linting.

## 0.2.0 - 2026-07-07

- Added familiar Swift configuration through `BumperBowling.swift`.
- Loaded configurations the way SwiftPM loads `Package.swift`: compiled, cached, and run in a deny-default sandbox.
- Added the `bumper` CLI workflow for hooks and CI jobs, including `bumper config`.
- Made SwiftPM tags the canonical distribution path.
- Added consumer-owned rule vocabulary through `.bumper/Sources`.
- Added SwiftPM-native local rule packages through `.bumper/Package.swift` and the `BumperRules` product convention.
- Added `ComponentShape` and `AssertionShape` so repositories can define their own architecture vocabulary without Bumper Bowling shipping their tastes.
- Shipped a bundled Codex skill for agents composing Bumper Bowling rules.
- Made Bumper Bowling dogfood local shapes in `.bumper/Sources/BumperArchitecture.swift`.
- Tightened the public package surface to `BumperBowlingCore` and the `bumper` executable.
- Split DSL and SwiftSyntax support files by responsibility.
