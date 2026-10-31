#!/bin/bash
set -euo pipefail

package_root="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$package_root" --product bumper
bumper_binary="$(swift build --package-path "$package_root" --show-bin-path)/bumper"
task_root="$(mktemp -d "${TMPDIR:-/tmp}/bumper-journey.XXXXXX")"
trap 'rm -rf "$task_root"' EXIT
repository="$task_root/Repository with spaces"
mkdir -p "$repository/Sources/Features"

ln -s "$package_root" "$task_root/Renamed checkout"
(cd "$repository" && "$bumper_binary" init --package-path "$task_root/Renamed checkout")
"$bumper_binary" test --help > /dev/null
"$bumper_binary" test "$repository"
printf '%s\n' 'struct DocumentView: View {}' '#Preview { DocumentView() }' > "$repository/Sources/Features/DocumentView.swift"
"$bumper_binary" lint "$repository"

# Observe dependency artifact reuse across a real rule edit, not a mocked build.
artifact="$(find "$repository/.bumper/.build" -type f \( -name 'SwiftSyntax.swiftmodule' -o -path '*/SwiftSyntax.swiftmodule/*.swiftmodule' \) -print -quit)"
test -n "$artifact"
before="$(stat -f '%i:%m:%z' "$artifact")"
printf '%s\n' 'struct DocumentView: View {}' > "$repository/Sources/Features/DocumentView.swift"
set +e
finding="$("$bumper_binary" lint "$repository" 2>"$task_root/lint.stderr")"
status=$?
set -e
test "$status" -eq 1
case "$finding" in
  *"Sources/Features/DocumentView.swift:1:1: error:"*"app.swiftui_preview"*) ;;
  *) printf 'Missing expected native diagnostic:\n%s\n' "$finding" >&2; exit 1 ;;
esac
rule="$repository/.bumper/Sources/BumperRules/SwiftUIPreviewRule.swift"
sed -i '' 's/inheriting("View")/inheriting("UnusedProtocol")/' "$rule"
"$bumper_binary" lint "$repository"
test "$(stat -f '%i:%m:%z' "$artifact")" = "$before"

# A consumer failure must reach the CLI, rather than become an empty result.
sed -i '' 's/inheriting("UnusedProtocol")/inheriting("View")/' "$rule"
printf '\nimport Testing\n@Test func intentionalFailure() { #expect(false) }\n' >> "$repository/.bumper/Tests/BumperRulesTests/SwiftUIPreviewRuleTests.swift"
if "$bumper_binary" test "$repository" >"$task_root/failed-tests.log" 2>&1; then
    printf 'Consumer test failure was lost.\n' >&2
    exit 1
fi

# Check the actual lint process boundary, with an unrestricted negative control.
cat > "$repository/.bumper/Sources/BumperRules/IsolationProbe.swift" <<'PROBE'
import BumperBowlingCore
import Foundation
public struct IsolationProbe: SyntaxRule {
    public static let metadata = RuleMetadata(id: "runtime.isolation", summary: "Lint isolates rule execution")
    public static var body: SyntaxCheck {
        Rules.files { file in
            let marker = file.root.appendingPathComponent("sandbox-marker")
            var wrote = false
            do { try "probe".write(to: marker, atomically: false, encoding: .utf8); wrote = true } catch {}
            if wrote || ProcessInfo.processInfo.environment["BUMPER_PROBE_SECRET"] != nil {
                return [file.failure(at: file.syntax, message: "Execution was not isolated")]
            }
            return []
        }
    }
}
PROBE
cat > "$repository/.bumper/Sources/BumperRulesRunner/main.swift" <<'PROBE'
import BumperBowlingCore
import BumperRules
BumperProject { IsolationProbe.self }.main()
PROBE
BUMPER_PROBE_SECRET=hidden "$bumper_binary" lint "$repository"
test ! -e "$repository/sandbox-marker"
probe_binary="$(swift build --package-path "$repository/.bumper" --show-bin-path)/BumperRulesRunner"
set +e
BUMPER_PROBE_SECRET=visible "$probe_binary" "$repository" >"$task_root/unrestricted.log" 2>&1
probe_status=$?
set -e
test "$probe_status" -eq 1
test -f "$repository/sandbox-marker"
cp "$package_root/Sources/BumperBowlingCore/Starter/Sources/BumperRulesRunner/main.swift" "$repository/.bumper/Sources/BumperRulesRunner/main.swift"

# Export one convention as a normal package, then consume only that type elsewhere.
case "$(cat "$task_root/failed-tests.log")" in
  *"intentionalFailure()"*"failed"*) ;;
  *) printf 'The expected failing test did not run.\n' >&2; exit 1 ;;
esac
shared="$task_root/SharedConventions"
mkdir -p "$shared/Sources/BumperRules"
cp "$rule" "$shared/Sources/BumperRules/SwiftUIPreviewRule.swift"
sed -i '' 's/inheriting("UnusedProtocol")/inheriting("View")/' "$shared/Sources/BumperRules/SwiftUIPreviewRule.swift"
cat > "$shared/Package.swift" <<MANIFEST
// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "SharedConventions", platforms: [.macOS(.v15)],
    products: [.library(name: "BumperRules", targets: ["BumperRules"])],
    dependencies: [.package(name: "BumperBowling", path: "$package_root")],
    targets: [.target(name: "BumperRules", dependencies: [.product(name: "BumperBowlingCore", package: "BumperBowling")])])
MANIFEST
second="$task_root/Second repository"
mkdir -p "$second/.bumper/Sources/BumperRulesRunner" "$second/.bumper/Tests/SecondRulesTests" "$second/Sources/Features"
cat > "$second/.bumper/Package.swift" <<MANIFEST
// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "SecondRepository", platforms: [.macOS(.v15)],
    dependencies: [.package(path: "$shared"), .package(name: "BumperBowling", path: "$package_root")],
    targets: [.executableTarget(name: "BumperRulesRunner", dependencies: [
        .product(name: "BumperRules", package: "SharedConventions"),
        .product(name: "BumperBowlingCore", package: "BumperBowling")]),
        .testTarget(name: "SecondRulesTests", dependencies: [
            .product(name: "BumperRules", package: "SharedConventions"),
            .product(name: "BumperBowlingTestSupport", package: "BumperBowling")])])
MANIFEST
cp "$package_root/Sources/BumperBowlingCore/Starter/Tests/BumperRulesTests/SwiftUIPreviewRuleTests.swift" "$second/.bumper/Tests/SecondRulesTests/SwiftUIPreviewRuleTests.swift"
cp "$repository/.bumper/Sources/BumperRulesRunner/main.swift" "$second/.bumper/Sources/BumperRulesRunner/main.swift"
printf '%s\n' 'struct SecondView: View {}' '#Preview { SecondView() }' > "$second/Sources/Features/SecondView.swift"
"$bumper_binary" test "$second"
"$bumper_binary" lint "$second"
printf '%s\n' 'struct SecondView: View {}' > "$second/Sources/Features/SecondView.swift"
set +e
shared_finding="$("$bumper_binary" lint "$second" 2>"$task_root/shared.stderr")"
shared_status=$?
set -e
test "$shared_status" -eq 1
case "$shared_finding" in
  *"SecondView needs a #Preview that constructs SecondView"*"app.swiftui_preview"*) ;;
  *) printf 'Shared rule did not preserve its diagnostic.\n' >&2; exit 1 ;;
esac
printf '\377' > "$second/Sources/Features/SecondView.swift"
set +e
"$bumper_binary" lint "$second" >"$task_root/invalid-input.log" 2>&1
input_status=$?
set -e
test "$input_status" -eq 2
printf '%s\n' 'struct SecondView: View {}' '#Preview { SecondView() }' > "$second/Sources/Features/SecondView.swift"
printf '\nthis is invalid Swift\n' >> "$second/.bumper/Sources/BumperRulesRunner/main.swift"
set +e
"$bumper_binary" lint "$second" >"$task_root/invalid-rule.log" 2>&1
build_status=$?
set -e
test "$build_status" -eq 2
printf 'Generated fixtures, lint exits, rule edits, dependency reuse, isolation, and shared rule consumption passed.\n'
