import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("RepositoryScanner Safety")
struct RepositoryScannerSafetyTests {
    @Test(arguments: [false, true])
    func rejectsSymlinkedSwiftFiles(withArchitecture: Bool) async throws {
        let temp = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temp)
        }
        let root = temp.appendingPathComponent("Repo")
        let outside = temp.appendingPathComponent("Outside")
        let outsideFile = outside.appendingPathComponent("Secret.swift")
        let symlink = root.appendingPathComponent("Sources/Core/Secret.swift")

        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "public struct Secret {}\n".write(to: outsideFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outsideFile)

        let scanner = try RepositoryScanner(configuration: withArchitecture ? configuration : ArchitectureConfiguration())

        do {
            _ = try await scanner.scan(root: root)
            #expect(Bool(false), "Expected symlinked Swift file to be rejected.")
        } catch let error as BumperError {
            #expect(error.description.contains("symlinked Swift source file"))
        }
    }

    @Test
    func rejectsExplicitFilesOutsideRoot() async throws {
        let temp = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temp)
        }
        let root = temp.appendingPathComponent("Repo")
        let outside = temp.appendingPathComponent("Outside")
        let outsideFile = outside.appendingPathComponent("Core.swift")

        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources/Core"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "public struct Core {}\n".write(to: outsideFile, atomically: true, encoding: .utf8)

        let scanner = try RepositoryScanner(configuration: configuration)

        do {
            _ = try await scanner.scanFile(outsideFile, root: root)
            #expect(Bool(false), "Expected out-of-root Swift file to be rejected.")
        } catch let error as BumperError {
            #expect(error.description.contains("outside repository root"))
        }
    }

    @Test(arguments: [false, true])
    func rejectsScansThatExceedFileCountLimit(withArchitecture: Bool) async throws {
        let root = try makeRepository(files: [
            "Sources/Core/One.swift": "public struct One {}\n",
            "Sources/Core/Two.swift": "public struct Two {}\n",
        ])
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let scanner = try RepositoryScanner(
            configuration: withArchitecture ? configuration : ArchitectureConfiguration(),
            limits: RepositoryScanLimits(maxFiles: 1)
        )

        do {
            _ = try await scanner.scan(root: root)
            #expect(Bool(false), "Expected scan file count limit to be enforced.")
        } catch let error as BumperError {
            #expect(error.description.contains("More than 1 Swift source files"))
        }
    }

    @Test(arguments: [false, true])
    func rejectsFilesThatExceedByteLimit(withArchitecture: Bool) async throws {
        let root = try makeRepository(files: [
            "Sources/Core/Large.swift": "public struct Large { let value = \"0123456789\" }\n",
        ])
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let scanner = try RepositoryScanner(
            configuration: withArchitecture ? configuration : ArchitectureConfiguration(),
            limits: RepositoryScanLimits(maxFileBytes: 10)
        )

        do {
            _ = try await scanner.scan(root: root)
            #expect(Bool(false), "Expected scan byte limit to be enforced.")
        } catch let error as BumperError {
            #expect(error.description.contains("limit is 10 bytes"))
        }
    }

    private var configuration: ArchitectureConfiguration {
        ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ]
        )
    }

    private func makeRepository(files: [String: String]) throws -> URL {
        let root = try makeTemporaryDirectory()
        for (path, source) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
