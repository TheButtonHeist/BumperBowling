# Repository conventions

Build your convention in `Sources/BumperRules/SwiftUIPreviewRule.swift`.
Its body is a builder: compose requirements, use ordinary Swift, and extract helpers.
Keep its examples alongside the rule to check its meaning.
Register additional Bumper or native SwiftLint rule types in `Sources/BumperRulesRunner/main.swift`.
Set the runner's `included` paths to the source roots your repository uses.

From the repository root:

```
bumper test .
bumper lint .
```

Or use SwiftPM directly:

```
swift test --package-path .bumper
swift run --package-path .bumper BumperRulesRunner .
```

Commit this package, its rules, tests, and `Package.resolved`. Ignore `.build`.
Builds and tests run trusted Swift code. `bumper lint` isolates the rule executable
with no writes or network and only its toolchain path in the environment.
Direct `swift run` does not apply that execution boundary.
