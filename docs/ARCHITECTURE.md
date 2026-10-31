# Bumper Bowling Architecture

Bumper Bowling is a Swift rule engine over SwiftSyntax-observed source facts.
The architecture DSL supplies optional ownership and dependency policy.

The configuration language is specified in [DSL_SPEC.md](DSL_SPEC.md). Bumper Bowling ships one engine and one dumb interface over that engine: the `bumper` CLI for shell workflows, CI jobs, and product tests.

Bumper Bowling is designed to feel familiar beside SwiftLint: rules, severities, included/excluded paths, opt-in rules, reports, and a primary `bumper lint` command.

It runs alongside SwiftLint; it does not replace SwiftLint. SwiftLint owns local Swift style and code smells. Bumper Bowling owns the project's architectural rules: what each component owns, may depend on, may use, and must prove from SwiftSyntax nodes.

SwiftPM is the canonical distribution path. Tagged versions of this repository
publish both the `BumperBowlingCore` library product and the `bumper`
executable product. Other installers can wrap the CLI later, but they should
not become the source of truth.

SwiftLint configuration lives in `.swiftlint.yml`.

The tool should stay tiny. Prefer a small SwiftSyntax-first core, simple Swift configuration constructors, and boring CLI behavior over generated accessors, dynamic lookup, plugins, or clever configuration machinery.

The interesting part is the assertion model, not the wrapper. Bumper Bowling turns SwiftSyntax-visible source facts into a graph, then evaluates typed Swift declarations against that graph. The CLI target is intentionally a thin delivery surface for hooks, CI, and product tests.

## Core Model

```text
The host collects all included Swift sources
RepositorySyntax parses each source once
Rules inspect syntax and shared derived facts
Architecture facts add component ownership and dependency edges
RuleSet produces one structured RuleReport
```

The lint run itself is modeled as an explicit reducer-backed state machine:
prepare rules, scan sources, evaluate rules, and report. Evaluation is
sequential in declaration order; the final report is sorted deterministically
by path, line, column, rule ID, then message.

Bumper Bowling is not a semantic analyzer. If SwiftSyntax cannot observe something, Bumper Bowling cannot truthfully assert it. Compiler-backed checks belong in a later, separate `analyze` lane; candidate requests are tracked in [COMPILER_REQUESTS.md](COMPILER_REQUESTS.md).

The current SwiftSyntax node surface is documented in [SWIFTSYNTAX_SURFACE.md](SWIFTSYNTAX_SURFACE.md).

## Configuration Loading

`BumperBowling.swift` loads the way SwiftPM loads `Package.swift`: it is a program, so it is compiled and run rather than parsed.

The project runner generates a small package that links `BumperBowlingCore`, compiles `BumperBowling.swift` into it, and builds it optimized (release configuration), and runs the product in a deny-default sandbox — no network, no writable paths, an empty environment. One cached executable serves two modes. `describe` prints the project's architecture configuration as JSON so the host knows what to scan. `evaluate` receives the scanned source files on stdin as Codable `RepositoryInput`, parses each file exactly once into `RepositorySyntax`, evaluates built-in and project rules in one `RuleSet`, and prints one Codable `EvaluationRun` — the canonical `RuleReport` plus per-rule and per-fact timing telemetry. Nothing else crosses back; scanning stays in the host process, never in configuration code, and rule code does not receive filesystem traversal.

The generated package and compiled output are cached. Before each runner invocation, SwiftPM checks whether sources, resources, or dependencies need rebuilding. An unchanged package uses an incremental build check. Rule and configuration edits reuse the same generated package directory, preserving dependency build products. Cache identity depends on the project and library paths, toolchain, and build configuration; SwiftPM tracks changed inputs. `bumper config` loads the configuration and reports whether it is valid.

The host uses nonblocking pipes to send sources and capture output. One monotonic time budget covers input transfer, execution, and output collection. Output limits remain enforced while the child runs.

In source mode, the cached package also owns one generated `BumperRuleTests`
target. `bumper test` fills that target from `BumperBowling.swift`,
`.bumper/Sources`, and `.bumper/Tests`, then delegates discovery and execution
to `swift test`. Test source identity is tracked separately from runner
identity: changing only a test refreshes and recompiles the test target without
invalidating the lint runner. When `.bumper` is a Swift package, `bumper test`
runs that package's ordinary test targets directly, preserving package-owned
`@testable` visibility. The test process is ordinary trusted SwiftPM test code,
not sandboxed configuration evaluation. It uses SwiftPM's ordinary debug test
default and does not prebuild the optimized lint runner. Source-mode cache
updates and test execution share an interprocess lock so concurrent invocations
cannot replace the generated target underneath one another. Source-mode tests use a separate generated-package cache from lint.
Lint cache preparation, builds, and execution also share a project lock. A process-local lock prevents concurrent threads from bypassing file locks.

A configuration should declare the architecture the repository wants, then lower into assertions over observed facts. Prefer `Component`, `Owns`, `MayDependOn`, `MayUse`, and scoped fact assertions over free-floating negative rules.

`scan` and `snapshot` expose the observed graph Bumper Bowling can build from
SwiftSyntax and repo shape. The graph holds the source files, component nodes,
dependency edges, computed source facts, and a raw SwiftSyntax node catalog.
That graph is evidence for the declared bounds, not a source of generated
policy.

SwiftSyntax remains the full source tree. Generic rules can inspect that tree
without component declarations. `ArchitectureGraph` is an optional projection
for architecture policy. Unowned files remain in source facts, while component
edges require ownership. Raw syntax checks use SwiftSyntax's `SyntaxKind`;
richer local checks use extensions on real nodes through `node.bumper`.

Add graph facts only when they support an assertion Bumper Bowling can explain. Rules should be lean mathematical operations over nodes: path matching, set membership, graph edges, and cycles. Keep scorecards explainable: report the observed graph fact, the declared lane, and why they do not match.

Semantic shorthand names are not special engine concepts.
`ComponentRequirement` composes `SourceFactRule` values, then `Requires(...)`
applies scope and severity. Built-in requirement conveniences and
repository-owned requirements lower into the same raw graph assertions.

Consumer repositories can place Swift files under `.bumper/Sources` to define
their own `ComponentRequirement`, `ComponentShape`, `AssertionShape`, and
custom rule vocabulary. Those files compile into the temporary configuration
runner beside `BumperBowling.swift`. They do not add a plugin boundary or hidden evaluator;
they are just consumer-owned Swift values that lower into the same
`ArchitectureConfiguration` data as inline configuration code, or into
`RuleDefinition` values the project adds to its `Rules` block.

Reusable vocabulary can also live in a conventional `.bumper/Package.swift`
SwiftPM package. The generated runner depends on its `BumperRules` library
product so `BumperBowling.swift` can import it; this does not discover,
download, or apply rules.

## Product Lane

Bumper Bowling lives between linting and compilation.

- SwiftLint owns local style, convention, and code smells.
- The compiler owns type checking, symbol resolution, macro expansion, and build truth.
- Bumper Bowling owns architectural rules when they can be checked from SwiftSyntax nodes and repo metadata.

That lane is especially useful for agentic work because it gives an automated editor a formal contract before it touches the repository, then leaves a scorecard after it does.

## Lanes

A lane is a declared architectural boundary.

Most lanes are `Component` values. A component lane has:

- owned paths
- module aliases
- allowed dependencies
- allowed capabilities
- scoped assertions

Some assertions use narrower lanes. `RequiresScoped(...)` and assertion path filters apply a rule to a specific path scope inside the repository.

Composed shapes preserve those narrower lanes as distinct rule settings. The
merged `RuleConfiguration` fields remain a compatibility summary, but the
validator evaluates the scoped settings list so severity, paths, and exclusions
stay attached to the clause that declared them.

The rule engine should always know which lane a finding came from. A report without a lane is hard to fix.

## Components

- `BumperBowlingCore` owns parsing, rule construction, repository scanning, architecture modeling, and linting.
- `BumperBowling` is the CLI adapter for hooks and CI jobs. It may depend on `BumperBowlingCore`; core must not depend on the CLI.
- Tests may import product modules and testing frameworks, but production targets must not import test frameworks.
- Language parsing is SwiftSyntax-driven. Swift is the only language surface.

## Architectural Rules

- Core domain rules must be represented as typed values before use.
- Swift configuration structs are boundary/input shapes only; scanning and validation operate on typed rules.
- Strings are parsed into domain types at boundaries. Core models should carry `ComponentID`, `ModuleName`, paths, declaration names, and attributes as types.
- Empty component names, module names, path prefixes, and unknown dependency references are invalid.
- Duplicate component IDs, module aliases, and path ownership are invalid.
- SwiftSyntax parsing is syntax-only. Reports must not imply compiler-level symbol resolution.
- Public API detection is syntactic and covers declarations marked `public` or `open`.
- Stateful parsers use explicit enum-based state machines. Stateless fact collection should stay as direct functional projection over SwiftSyntax nodes.
- Avoid `Any` and broad existential abstractions in domain code.
- Avoid code generation unless it directly supports a core linting workflow.

## Swift Rules

- Use Swift 6 strict concurrency.
- Public model types that cross component boundaries should be `Sendable`.
- Prefer immutable value types for parsed architecture state.
- Prefer `let` for domain data. Use local mutation only as a scoped builder detail when Swift APIs require callback-style accumulation.
- Do not add `@unchecked Sendable` without a local explanation.
- Do not use `swift build` for future iOS projects in this repo family; use `xcodebuild` when iOS SDK access matters.
