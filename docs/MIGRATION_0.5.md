# Migrating to 0.5.0

0.5.0 replaces the closed configuration surface and the separate custom-rule
worker with one open rule engine and one project entry point. There are no
compatibility aliases; every removed symbol has an exact replacement.

## Configuration

| Removed | Replacement |
| --- | --- |
| `BumperConfiguration { ... }` | `BumperProject { ... }` |
| `let configuration = ...` in `BumperBowling.swift` | `let bumper = BumperProject { ... }` |
| `configuration.architectureConfiguration` | `bumper.architecture` |
| `Assertions { ... }` | `Rules { ... }` |
| `CustomRules()` / `CustomRules(maxConcurrentRuleJobs:)` | Nothing — add project rules to `Rules { ... }`; there is no opt-in marker or worker concurrency knob. |
| `CustomRuleWorkerConfiguration` | Removed with no replacement (no second worker exists). |

`Architecture { ... }` is unchanged, and the new typed
`Architecture(MyComponentKey.self) { ... }` accepts your own `ComponentKey`
enum so `Component(.core)` / `MayDependOn(.core)` are compiler-checked.

## Custom rules

| Removed | Replacement |
| --- | --- |
| `CustomRuleSet { ... }` | `RuleSet { ... }` |
| `CustomRule("id", severity:) { context in ... }` | `Rules.repository("id", severity:, summary:) { context in ... }` |
| `CustomSyntaxRule("id", severity:) { file in ... }` | `Rules.files("id", severity:, summary:) { file in ... }` |
| `CustomRuleFailure` | `RuleFailure` |
| `CustomRuleInput` | `RepositoryInput` (host-to-runner wire type; rule code receives `RuleContext`) |
| `CustomRuleOutput` / `CustomRuleFinding` | `RuleReport` / `RuleViolation` |
| `CustomRuleFileFacts` | `SourceFileContext(descriptor:source:)` |
| `CustomRuleContext` | `RuleContext` |
| `context.files(inComponent:)` + `file.imports` | `context.facts(BuiltInFacts.imports).occurrences` (or any other `FactProvider`) |
| A top-level `let customRules` value | A `RuleSet` value referenced inside `Rules { ... }` |

## Reports and evaluation

### Generic source rules and scoped subjects

Component ownership is now optional source metadata. `SourceInput`,
`SourceFileDescriptor`, `SourceFileFacts`, and source occurrences use
`ComponentID?`. Existing owned inputs still decode. Unowned wire
inputs can omit the component field.

Use `component?.rawValue` for an optional display value. For component-specific
logic, require an owner explicitly. Do not assign a placeholder component.

The scanner passes every included Swift file to analysis. `scanSources` no
longer throws for an unowned file. `scannedFileCount` includes unowned Swift
files. `SourceCoverage` still reports missing and overlapping ownership when
enabled. Unsupported languages remain inventory entries without syntax trees.

Syntax-only projects can omit `Architecture`. Library callers can use
`RepositoryScanner(scan:)` and evaluate a `RuleSet` without architecture
configuration. Component configuration defaults to an empty array.

Unscoped repository closures keep their one-argument form. Scoped closures now
receive selected subjects and full context:

```swift
Rules.repository("project.policy", summary: "Project policy.", scope: selectedFiles) { subjects, context in
    let paths = Set(subjects.map(\.path))
    return try context.facts(BuiltInFacts.imports).occurrences
        .filter { paths.contains($0.path) && $0.module.rawValue == "UIKit" }
        .map { RuleFailure(path: $0.path, message: "UIKit import in selected sources.") }
}
```

This also applies to the scoped `RepositoryRule` initializer. An outside
diagnostic throws `RuleEvaluationError.diagnosticOutsideScope`; it never
disappears silently. A positive cardinality over an empty selected file scope
now fails explicitly. Negative cardinalities also fail explicitly.

The generic Markdown report uses rule terminology instead of architecture
terminology. JSON diagnostic fields remain unchanged.

### Existing evaluation types

| Removed | Replacement |
| --- | --- |
| `ArchitectureLinter` | `RuleSet.evaluate(configuration:repository:)` via `BumperProject.evaluate(_:)` |
| `LintReport` | `RuleReport` |
| `ArchitectureViolation` | `RuleViolation` (`ruleID` and `severity` are conveniences over `rule` metadata) |
| `RuleRegistry` | Nothing — rules are values in a `RuleSet`; there is no registry. |
| `RuleDescription` | `RuleMetadata` |
| `RuleSet.evaluateConcurrently(...)` | `RuleSet.evaluate(...)` — evaluation is sequential in V1. |

## Runner

The two cached executables (configuration runner and custom-rule worker) are
one cached `BumperProjectRunner` with two modes: `describe` emits the
architecture configuration as JSON; `evaluate` reads `RepositoryInput` from
stdin and emits one `RuleReport`. Cache locations honor `BUMPER_CACHE_DIR`
unchanged; caches from earlier versions are keyed differently and rebuild once.

## Rule test fixtures

Pass `[SourceInput]` directly to `RuleTestHarness.evaluate(_:)`.
`VirtualSourceFile`, `VirtualRepository`, and `VirtualRepositoryBuilder` are
removed. Use array literals, `map`, and ordinary conditionals for fixtures.

```swift
let report = try RuleTestHarness(rule).evaluate([
    SourceInput.swift("Sources/App.swift", component: "app", source: "struct App {}")
])
```

`SourceInput.swift` is a test-support convenience for validated string paths
and optional component names. Use the existing `SourceInput` initializer for
typed paths and `ComponentID` values.
