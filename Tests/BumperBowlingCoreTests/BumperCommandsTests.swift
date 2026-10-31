import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Ordinary rule packages")
struct BumperCommandsTests {
    @Test func initializationPreservesExistingConfiguration() throws {
        let root = try makeTestRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTestSource(root, "BumperBowling.swift", "existing configuration")
        #expect(throws: BumperError.self) { try BumperCommands.initialize(at: root) }
        #expect(try String(contentsOf: root.appendingPathComponent("BumperBowling.swift"), encoding: .utf8) == "existing configuration")
    }

    @Test func initializationWritesAnEditablePackageAndRefusesReplacement() throws {
        let root = try makeTestRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        try BumperCommands.initialize(at: root)
        let manifest = root.appendingPathComponent(".bumper/Package.swift")
        let original = try Data(contentsOf: manifest)
        #expect(throws: BumperError.self) { try BumperCommands.initialize(at: root) }
        #expect(try Data(contentsOf: manifest) == original)
    }
}
