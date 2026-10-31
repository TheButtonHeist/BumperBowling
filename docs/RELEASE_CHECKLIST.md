# Release checks

The SwiftLint-backed DSL starts with version 0.7.0. It changes public APIs and
the package workflow.

1. Run strict SwiftLint, the full package tests, repository rule tests, and self-lint.
2. Run `Scripts/verify-rule-journey.sh` from the checkout.
3. Build and run the native path in debug and release with the pinned toolchain.
4. Check that every canonical passing fixture is clean and every failing fixture matches its diagnostic.
5. Check the migration guide against the removed public APIs and commands.
6. Check source and process bounds, cache eviction, and dependency-build reuse.
7. Review the diff for an old evaluator, source-copy cache, direct parser call, or unnecessary abstraction.
8. Publish the intended package revision before advertising the default remote starter.

Record actual cold build, warm edit, and lint timings before making performance
claims. A smaller maintained Bumper codebase does not establish a smaller binary.
Adoption and usability claims still need developer trials against a direct
SwiftLintFramework baseline.
