import Foundation
import SwiftLintFramework
import Testing
@testable import BumperBowlingCore

@Suite("Bounded native source input")
struct RepositoryScannerSafetyTests {
    @Test(arguments: ["files", "fileBytes", "totalBytes", "utf8"])
    func rejectsInvalidInput(reason: String) throws {
        let root = try makeTestRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTestSource(root, "Sources/One.swift", "struct One {}")
        try writeTestSource(root, "Sources/Two.swift", "struct Two {}")
        let limits: RepositoryScanLimits
        switch reason {
        case "files": limits = .init(maxFiles: 1)
        case "fileBytes": limits = .init(maxFileBytes: 1)
        case "totalBytes": limits = .init(maxTotalBytes: 15)
        default:
            limits = .init()
            try Data([0xFF]).write(to: root.appendingPathComponent("Sources/One.swift"))
        }
        #expect(throws: BumperError.self) { try RepositoryScanner(limits: limits).scan(root: root) }
    }

    @Test func rejectsSymlinksAndOutsidePaths() throws {
        let parent = try makeTestRepository()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("Repo")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try writeTestSource(parent, "Secret.swift", "struct Secret {}")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Sources/Link.swift"), withDestinationURL: parent.appendingPathComponent("Secret.swift"))
        #expect(throws: BumperError.self) { try RepositoryScanner().scan(root: root) }
        #expect(throws: BumperError.self) { try RepositoryScanner(included: ["../Secret.swift"]).scan(root: root) }
    }

    @Test func preservesBoundedSnapshotAndExcludesBuildInputs() throws {
        let root = try makeTestRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTestSource(root, "Sources/Kept.swift", "struct Kept {}")
        try writeTestSource(root, "Sources/Generated/Ignored.swift", "struct Ignored {}")
        let files = try RepositoryScanner(included: ["Sources", "Sources/Kept.swift"], excluded: ["Sources/Generated"]).scan(root: root)
        #expect(files.count == 1)
        try writeTestSource(root, "Sources/Kept.swift", "struct Changed {}")
        #expect(files.first?.contents == "struct Kept {}")
    }
}

func makeTestRepository() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("bumper-test-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func writeTestSource(_ root: URL, _ path: String, _ source: String) throws {
    let file = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try source.write(to: file, atomically: true, encoding: .utf8)
}
