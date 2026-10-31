# Architecture

Bumper is a Swift DSL for repository conventions. SwiftLintFramework is its
runtime. SwiftSyntax supplies the source tree and syntax node types.

```text
Repository Swift package
  BumperProject -> named SyntaxRule / RepositoryRule types
                         |
  syntax queries -> policy body -> located RuleFailure values
                         |
  SwiftLint configuration, collection, validation, and reporting
                         |
                    StyleViolation
```

## Ownership

Bumper owns the readable policy vocabulary, repository-relative scopes,
diagnostic construction, paired fixture support, package starter, commands,
and input and process bounds.

SwiftLint owns cached parsing, native rule execution, per-rule cross-file
storage, disable directives, severity types, and standard reporting. Every DSL
rule has its own native rule type and identifier. Native rules can be registered
alongside DSL rules.

SwiftPM owns dependency resolution, compilation, and build reuse. The committed
`.bumper/Package.swift` is the only package mode. There is no generated runner
manifest, source-copy cache, describe/evaluate protocol, or second evaluator.

## Execution

1. `bumper lint` builds the repository package’s `BumperRulesRunner` product.
2. The bounded command helper runs that executable in the sandbox with the repository root.
3. The scanner reads bounded UTF-8 source snapshots from included paths.
4. The runner configures each DSL rule with the repository root.
5. Duplicate IDs and invalid required subject selections fail preflight.
6. Every included file is collected into one SwiftLint `RuleStorage`.
7. SwiftLint validates files after collection completes.
8. Bumper checks DSL diagnostic scopes and normalizes paths for reporting.

`RepositoryRule.FileInfo` holds typed observations for one file. Collection
covers all included files; a scope selects subjects for validation. Bumper has
no generic shared-fact cache. A file context retains the source and syntax
snapshot needed by collected matches when SwiftLint evicts its file caches.

The violation cache is disabled. Editing a rule or companion file therefore
changes the next run without a custom invalidation protocol. SwiftPM build
caching remains enabled and has a real rule-edit acceptance check.

## Runtime contracts

| Boundary | Contract |
| --- | --- |
| Source input | At most 20,000 Swift files, 10 MiB per file, and 200 MiB total |
| Paths | Repository-relative includes; no source symlinks or root escapes |
| Text | Valid UTF-8; supply the bounded snapshot before native parsing |
| Build | 600-second timeout; 4 MiB per captured output stream |
| Lint execution | 60-second default timeout; 4 MiB per captured output stream |
| Consumer tests | Interactive ordinary `swift test`, with inherited terminal I/O |
| Findings | Native warning/error severity; errors exit 1 and warnings exit 0 |
| Host failures | Nonzero status; runner preflight failures exit 2 |

`BUMPER_EVALUATION_TIMEOUT_SECONDS` accepts positive finite seconds.
`BUMPER_RUNNER_BUILD_CONFIGURATION` accepts `debug` or `release`; the default is
debug. The bounded process helper retains its timeout, pipe, large-input, and
closed-input regression tests.

Builds and consumer tests run trusted Swift code with normal process access.
`bumper lint` retains the deny-default evaluation sandbox: reads are allowed;
writes and network are denied. Its environment contains only `TOOLCHAIN_DIR`,
resolved from the selected Swift toolchain before entering the sandbox.
SourceKitten needs that library path even for syntax-only execution.
Direct `swift run` bypasses the CLI execution boundary.

The scanner retains Bumper’s path and resource checks because native discovery
does not supply the same contract. It does not parse source. The DSL requests
SwiftLint’s cached tree and never calls `Parser.parse`.

## Dependency boundary

The verified pair is SwiftLint 0.63.3 and SwiftSyntax
604.0.0-prerelease-2026-04-21, built with Swift 6.4. Newer SwiftLint releases
pin different SwiftSyntax versions. Upgrade both through the compiled DSL,
fixture, runner, and runtime checks.

Bumper requires `SourceKitFreeRule` and supplies no compiler arguments. It does
not request SourceKit analysis. SwiftLintFramework still brings its transitive
library dependencies; a smaller Bumper codebase does not imply a smaller binary
or faster clean build.

Collection is supplied to each selected subject file. Keep subject scopes narrow
when repository aggregation is expensive; no shared aggregate cache is implied.
