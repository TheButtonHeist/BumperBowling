import BumperBowlingCore
import Foundation

@main
struct BumperCLI {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let command = arguments.first ?? "help"
            if ["help", "--help", "-h"].contains(command) {
                print(help)
                return
            }
            var remaining = Array(arguments.dropFirst())
            if remaining == ["--help"] || remaining == ["-h"] {
                print(help)
                return
            }
            var packagePath: URL?
            if command == "init", let flag = remaining.firstIndex(of: "--package-path") {
                guard flag + 1 < remaining.count, !remaining[flag + 1].hasPrefix("-") else { throw BumperError(help) }
                packagePath = URL(fileURLWithPath: remaining[flag + 1])
                remaining.removeSubrange(flag...(flag + 1))
            }
            guard remaining.count <= 1, !remaining.contains(where: { $0.hasPrefix("-") }) else { throw BumperError(help) }
            let root = URL(fileURLWithPath: remaining.first ?? FileManager.default.currentDirectoryPath)
            switch command {
            case "init":
                try BumperCommands.initialize(at: root, packagePath: packagePath)
                print("Created .bumper. Edit its rule and examples, then run bumper test and bumper lint.")
            case "lint": Foundation.exit(try BumperCommands.lint(root: root))
            case "test": Foundation.exit(try BumperCommands.test(root: root))
            default: throw BumperError("Unknown command: \(command)\n\(help)")
            }
        } catch {
            FileHandle.standardError.write(Data("bumper: \(error)\n".utf8))
            Foundation.exit(2)
        }
    }

    private static let help = """
    Bumper Bowling — tested repository conventions, powered by SwiftLint.

    bumper init [root] [--package-path <Bumper checkout>]
    bumper test [root]
    bumper lint [root]

    Commit .bumper's package, rules, tests, and Package.resolved.
    Builds and tests run trusted Swift code. Lint rules cannot write or use the network.
    Lint exits 1 for error violations and 2 for host failures. Warnings do not fail.
    Tests preserve Swift Testing's exit status.
    """
}
