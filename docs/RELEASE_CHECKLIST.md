# Release Checklist

SwiftPM tags are the canonical distribution artifact for Bumper Bowling.
Run these checks on the release candidate before tagging it.

1. Check that `LICENSE` is Apache 2.0.
2. Check that `Package.swift` exposes only the intended public products.
3. Run `swift package dump-package`.
4. Run `swiftlint lint --strict`.
5. Run `BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift test`.
   This includes runtime tests for timeouts, pipes, cache safety, and dependency-build reuse.
6. Run `BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift run bumper test .`.
   Both passing and failing repository-policy fixtures must pass.
7. Run `BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift run bumper lint .`.
8. Compare `bumper snapshot .` with `docs/ARCHITECTURE_SNAPSHOT.md`.
   Use `BUMPER_RUNNER_BUILD_CONFIGURATION=debug` for this command too.
9. Check that the README dependency names the release version.
10. Check that the README examples and linked API guides match the release candidate.
11. Check that the release notes describe API removals, replacements, and behavior changes since the previous tag.
    Release notes belong in the GitHub release description.
12. In a fresh consumer package, depend on the candidate commit and run `swift run bumper init .`.
13. Run `swift run bumper lint .` in that consumer with `BUMPER_RUNNER_BUILD_CONFIGURATION` unset.
    This checks the default optimized runner with a fresh cache.
14. Add one passing and one failing source example for a consumer rule.
    Check the failing diagnostic and a nonzero exit status with `--fail-on error`.
15. Check that GitHub Actions is green on the final candidate commit on `main`.
16. Tag that commit with the release version, for example `git tag 0.7.0`.
17. Push the tag, for example `git push origin 0.7.0`.
18. Publish the GitHub release with its release notes.
