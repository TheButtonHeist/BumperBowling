import Foundation
import SwiftLintFramework

public struct RepositoryScanLimits: Sendable {
    public let maxFiles: Int
    public let maxFileBytes: Int
    public let maxTotalBytes: Int

    public init(maxFiles: Int = 20_000, maxFileBytes: Int = 10 * 1024 * 1024, maxTotalBytes: Int = 200 * 1024 * 1024) {
        self.maxFiles = max(1, maxFiles)
        self.maxFileBytes = min(Int.max - 1, max(1, maxFileBytes))
        self.maxTotalBytes = max(1, maxTotalBytes)
    }
}

/// Discovers bounded input before SwiftLint reads or parses it.
public struct RepositoryScanner: Sendable {
    private let included: [String]
    private let excluded: [String]
    private let limits: RepositoryScanLimits

    public init(included: [String] = ["Sources"], excluded: [String] = [], limits: RepositoryScanLimits = .init()) {
        self.included = included
        self.excluded = excluded
        self.limits = limits
    }

    public func scan(root: URL) throws -> [SwiftLintFile] {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let canonicalRoot = root.resolvingSymlinksInPath().path
        var files: [SwiftLintFile] = []
        var seen: Set<String> = []
        var totalBytes = 0
        for path in excluded { try Self.validateRelativePath(path) }
        guard !included.isEmpty else { throw BumperError("Include at least one source path.") }
        for path in included {
            try Self.validateRelativePath(path)
            let url = root.appendingPathComponent(path).standardizedFileURL
            try validateContainment(url, root: canonicalRoot)
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
                throw BumperError("Included source path does not exist: \(path)")
            }
            if !directory.boolValue {
                try append(url, root: root, canonicalRoot: canonicalRoot, seen: &seen, totalBytes: &totalBytes, files: &files)
                continue
            }
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw BumperError("Refusing symlinked source directory: \(path)") }
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles], errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            ) else { throw BumperError("Could not enumerate sources: \(path)") }
            for case let discovered as URL in enumerator {
                let file = discovered.deletingLastPathComponent().standardizedFileURL.appendingPathComponent(discovered.lastPathComponent)
                let relative = String(file.path.dropFirst(root.path.count + 1))
                if isExcluded(relative) {
                    enumerator.skipDescendants()
                    continue
                }
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    throw BumperError("Refusing symlinked source path: \(relative)")
                }
                if values.isRegularFile == true {
                    try append(file, root: root, canonicalRoot: canonicalRoot, seen: &seen, totalBytes: &totalBytes, files: &files)
                }
            }
            if let enumerationError { throw enumerationError }
        }
        guard !files.isEmpty else { throw BumperError("No Swift source files matched the included paths.") }
        return files.sorted { ($0.path ?? "") < ($1.path ?? "") }
    }

    private func append(
        _ url: URL, root: URL, canonicalRoot: String, seen: inout Set<String>,
        totalBytes: inout Int, files: inout [SwiftLintFile]
    ) throws {
        let path = String(url.path.dropFirst(root.path.count + 1))
        guard url.pathExtension == "swift", !isExcluded(path), seen.insert(path).inserted else { return }
        try validateContainment(url, root: canonicalRoot)
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw BumperError("Refusing symlinked Swift source file: \(path)") }
        guard values.isRegularFile == true else { throw BumperError("Could not read source file: \(path)") }
        guard files.count < limits.maxFiles else { throw BumperError("More than \(limits.maxFiles) Swift source files matched.") }
        guard values.fileSize ?? 0 <= limits.maxFileBytes else { throw BumperError("Source file exceeds \(limits.maxFileBytes) bytes: \(path)") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limits.maxFileBytes + 1) ?? Data()
        guard data.count <= limits.maxFileBytes else { throw BumperError("Source file exceeds \(limits.maxFileBytes) bytes: \(path)") }
        guard data.count <= limits.maxTotalBytes - totalBytes else { throw BumperError("Swift sources exceed \(limits.maxTotalBytes) total bytes.") }
        totalBytes += data.count
        guard let source = String(data: data, encoding: .utf8) else { throw BumperError("Source file is not UTF-8: \(path)") }
        let file = SwiftLintFile(pathDeferringReading: url.path)
        // Supply the bounded UTF-8 snapshot before SwiftLint can read or parse it.
        file.file.contents = source
        files.append(file)
    }

    private func isExcluded(_ path: String) -> Bool {
        ([".build", ".git", "DerivedData"] + excluded).contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func validateContainment(_ url: URL, root: String) throws {
        guard url.resolvingSymlinksInPath().path.hasPrefix(root + "/") else {
            throw BumperError("Source path is outside repository root \(root): \(url.path)")
        }
    }

    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BumperError("Expected a repository-relative path: \(path)")
        }
    }
}
