import Foundation

public enum BumperCommands {
    public static func initialize(at root: URL, packagePath: URL? = nil) throws {
        let destination = root.appendingPathComponent(".bumper")
        guard !FileManager.default.fileExists(atPath: destination.path),
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("BumperBowling.swift").path) else {
            throw BumperError("Bumper configuration already exists. See docs/MIGRATION.md before changing it.")
        }
        if let packagePath, !FileManager.default.fileExists(atPath: packagePath.appendingPathComponent("Package.swift").path) {
            throw BumperError("No Swift package found at \(packagePath.path).")
        }
        guard let starter = Bundle.module.url(forResource: "Starter", withExtension: nil) else {
            throw BumperError("The Bumper starter resources are missing.")
        }
        let staging = root.appendingPathComponent(".bumper-init-\(UUID())")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: starter, to: staging)
        let template = staging.appendingPathComponent("Package.swift.template")
        let dependency = packagePath.map { ".package(name: \"BumperBowling\", path: \(String(reflecting: $0.standardizedFileURL.path)))" }
            ?? ".package(url: \"https://github.com/TheButtonHeist/BumperBowling.git\", branch: \"main\")"
        let manifest = try String(contentsOf: template, encoding: .utf8).replacingOccurrences(of: "__BUMPER_DEPENDENCY__", with: dependency)
        try manifest.write(to: staging.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: template)
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    public static func lint(root: URL) throws -> Int32 {
        try ConfigurationLoader.runPackage(root: root)
    }

    public static func test(root: URL) throws -> Int32 {
        try ConfigurationLoader.runSwiftTests(packageRoot: packageRoot(root))
    }

    static func packageRoot(_ root: URL) throws -> URL {
        let package = root.appendingPathComponent(".bumper")
        guard FileManager.default.fileExists(atPath: package.appendingPathComponent("Package.swift").path) else {
            throw BumperError("No .bumper/Package.swift found. Run bumper init, or migrate the old configuration with docs/MIGRATION.md.")
        }
        return package
    }
}
