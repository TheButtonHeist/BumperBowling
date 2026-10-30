import Darwin
import CryptoKit
import Foundation

public extension ConfigurationLoader {
    /// Loads `BumperBowling.swift` the way SwiftPM loads `Package.swift`:
    /// compile the project into one cached runner, run its `describe` mode in
    /// a sandbox, read back the configuration it prints. The build is cached
    /// against the project source fingerprint, so the compile happens once
    /// per change, not once per lint.
    static func loadConfiguration(root: URL) throws -> ArchitectureConfiguration {
        let output = try runProjectRunner(
            root: root.standardizedFileURL,
            mode: .describe,
            input: nil
        )
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty configuration payload")
        }
        return try JSONDecoder().decode(ArchitectureConfiguration.self, from: Data(output.utf8))
    }

    /// Runs the same cached runner in `evaluate` mode: the bounded repository
    /// input goes in over stdin, one canonical report plus its telemetry
    /// comes back. Built-in and project rules execute in the same
    /// evaluation invocation.
    static func evaluateRun(root: URL, input: RepositoryInput) throws -> EvaluationRun {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let output = try runProjectRunner(
            root: root.standardizedFileURL,
            mode: .evaluate,
            input: try encoder.encode(input)
        )
        guard !output.isEmpty else {
            throw BumperError.configurationOutputMalformed("empty rule report payload")
        }
        return try JSONDecoder().decode(EvaluationRun.self, from: Data(output.utf8))
    }
}

/// The cached runner's typed modes, selected by its process arguments.
enum ProjectRunnerMode: String, Sendable {
    case describe
    case evaluate
}

extension ConfigurationLoader {
    /// The default evaluation budget in seconds. Legitimately large projects
    /// raise it with `BUMPER_EVALUATION_TIMEOUT_SECONDS`; evaluation is
    /// always bounded.
    static let configurationEvaluationTimeoutSeconds: TimeInterval = 60
    static let evaluationTimeoutEnvironmentKey = "BUMPER_EVALUATION_TIMEOUT_SECONDS"
    /// The runner is a cached artifact built once per configuration change,
    /// so it builds optimized by default: evaluation parses every scanned
    /// source and derives facts, where debug-mode swift-syntax is several
    /// times slower.
    static let defaultProjectRunnerBuildConfiguration = "release"
    static let runnerBuildConfigurationEnvironmentKey = "BUMPER_RUNNER_BUILD_CONFIGURATION"
    static let supportedRunnerBuildConfigurations: Set<String> = ["release", "debug"]

    /// The validated evaluation budget: the documented default when the
    /// override is absent, a positive finite number of seconds when present,
    /// and a loud configuration error otherwise. Invalid input can never
    /// produce an unbounded or zero-length budget.
    static func configurationEvaluationTimeout(
        environment: [String: String]
    ) throws -> TimeInterval {
        guard let raw = environment[evaluationTimeoutEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return configurationEvaluationTimeoutSeconds
        }
        guard let seconds = Double(raw), seconds.isFinite, seconds > 0 else {
            throw BumperError.invalidEvaluationTimeout(raw)
        }
        return seconds
    }

    /// The validated runner build configuration: release by default, debug
    /// only through the documented override (for build-constrained hosts like
    /// CI where cold optimized builds are too expensive), and a loud
    /// configuration error for anything else. Cache identity records the
    /// configuration, so the two never share an executable.
    static func projectRunnerBuildConfiguration(
        environment: [String: String]
    ) throws -> String {
        guard let raw = environment[runnerBuildConfigurationEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return defaultProjectRunnerBuildConfiguration
        }
        guard supportedRunnerBuildConfigurations.contains(raw) else {
            throw BumperError.invalidRunnerBuildConfiguration(raw)
        }
        return raw
    }

    static func cachedRunnerBuildArguments(packageRoot: URL, buildConfiguration: String) -> [String] {
        [
            "swift",
            "build",
            "--configuration",
            buildConfiguration,
            "--package-path",
            packageRoot.path,
            "--product",
            projectRunnerProductName,
        ]
    }

    static func cachedRunnerExecutableURL(in root: URL, productName: String, buildConfiguration: String) -> URL {
        root.appendingPathComponent(".build/\(buildConfiguration)/\(productName)")
    }

    static func makeCachedPackage(
        configurationURL: URL,
        bumperPackageRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CachedPackage {
        let buildConfiguration = try projectRunnerBuildConfiguration(environment: environment)
        let configurationData = try Data(contentsOf: configurationURL)
        let repositoryRoot = configurationURL.deletingLastPathComponent()
        let rulePackages = try rulePackageDependencies(root: repositoryRoot)
        let consumerSources = try rulePackages.isEmpty ? consumerConfigurationSources(root: repositoryRoot) : []
        let consumerSourcesHash = consumerConfigurationSourcesHash(consumerSources)
        let rulePackagesHash = try rulePackageDependenciesHash(rulePackages)
        let manifest = packageManifest(
            bumperPackageRoot: bumperPackageRoot,
            rulePackages: rulePackages,
            runnerProductName: projectRunnerProductName
        )
        let metadata = CachedPackageMetadata(
            configurationContentHash: sha256Hex(configurationData),
            consumerSourcesHash: consumerSourcesHash,
            rulePackagesHash: rulePackagesHash,
            runnerProductName: projectRunnerProductName,
            buildConfiguration: buildConfiguration
        )
        let root = try cachedPackageRoot(
            configurationURL: configurationURL,
            bumperPackageRoot: bumperPackageRoot,
            buildConfiguration: buildConfiguration,
            manifest: manifest,
            consumerSourcesHash: consumerSourcesHash,
            rulePackagesHash: rulePackagesHash,
            cacheRoot: configurationCacheRoot(environment: environment)
        )
        let sources = root.appendingPathComponent("Sources/\(projectRunnerProductName)")
        let consumerTests = root.appendingPathComponent("Tests/\(consumerTestTargetName)")
        let executableURL = cachedRunnerExecutableURL(
            in: root,
            productName: projectRunnerProductName,
            buildConfiguration: buildConfiguration
        )

        if cachedPackageIsCurrent(
            root: root,
            metadata: metadata,
            manifest: manifest,
            configurationData: configurationData,
            consumerSources: consumerSources
        ) {
            return CachedPackage(
                root: root,
                executableURL: executableURL,
                productName: projectRunnerProductName,
                buildConfiguration: buildConfiguration,
                needsBuild: !cachedExecutableIsCurrent(
                    executableURL,
                    metadataURL: root.appendingPathComponent(CachedPackageMetadata.fileName)
                )
            )
        }

        if FileManager.default.fileExists(atPath: sources.path) {
            try FileManager.default.removeItem(at: sources)
        }
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: consumerTests, withIntermediateDirectories: true)
        try manifest.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try configurationData.write(to: sources.appendingPathComponent("UserConfiguration.swift"), options: .atomic)
        try writeConsumerConfigurationSources(consumerSources, to: sources.appendingPathComponent("ConsumerSources"))
        try runnerSource.write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try consumerTestPlaceholder.write(
            to: consumerTests.appendingPathComponent("Placeholder.swift"),
            atomically: true,
            encoding: .utf8
        )
        try JSONEncoder()
            .encode(metadata)
            .write(to: root.appendingPathComponent(CachedPackageMetadata.fileName), options: .atomic)

        return CachedPackage(
            root: root,
            executableURL: executableURL,
            productName: projectRunnerProductName,
            buildConfiguration: buildConfiguration,
            needsBuild: true
        )
    }

    static func runConsumerTests(root: URL) throws -> Int32 {
        try runConsumerTests(
            root: root,
            bumperPackageRoot: bumperPackageRoot(),
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func runConsumerTests(
        root: URL,
        bumperPackageRoot: URL,
        environment: [String: String]
    ) throws -> Int32 {
        let root = root.standardizedFileURL
        let configurationURL = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw BumperError.configurationMissing(configurationURL.path)
        }

        let consumerPackageRoot = root.appendingPathComponent(consumerPackageDirectory)
        if FileManager.default.fileExists(atPath: consumerPackageRoot.appendingPathComponent("Package.swift").path) {
            return try runSwiftTests(packageRoot: consumerPackageRoot)
        }

        let testSources = try consumerTestSources(root: root)
        guard !testSources.isEmpty else {
            throw BumperError.consumerTestsMissing(
                root.appendingPathComponent(consumerTestDirectory).path
            )
        }

        var testEnvironment = environment
        // Consumer tests must not rewrite sources in an active lint build.
        testEnvironment[configurationCacheEnvironmentKey] = configurationCacheRoot(environment: environment)
            .appendingPathComponent("ConsumerTests").path
        return try withProjectCacheLock(root: root, environment: testEnvironment) {
            let consumerTests = try makeCachedConsumerTestPackage(
                root: root,
                bumperPackageRoot: bumperPackageRoot,
                environment: testEnvironment
            )
            return try runSwiftTests(packageRoot: consumerTests.package.root)
        }
    }

    static func runSwiftTests(packageRoot: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = consumerTestArguments(packageRoot: packageRoot)
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func consumerTestArguments(packageRoot: URL) -> [String] {
        [
            "swift",
            "test",
            "--package-path",
            packageRoot.path,
        ]
    }

    static func makeCachedConsumerTestPackage(
        root: URL,
        bumperPackageRoot: URL,
        environment: [String: String]
    ) throws -> CachedConsumerTestPackage {
        let root = root.standardizedFileURL
        let configurationURL = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw BumperError.configurationMissing(configurationURL.path)
        }

        let testSources = try consumerTestSources(root: root)
        guard !testSources.isEmpty else {
            throw BumperError.consumerTestsMissing(
                root.appendingPathComponent(consumerTestDirectory).path
            )
        }

        let rulePackages = try rulePackageDependencies(root: root)
        let consumerSources = try rulePackages.isEmpty ? consumerConfigurationSources(root: root) : []
        let configurationData = try Data(contentsOf: configurationURL)
        let package = try makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: bumperPackageRoot,
            environment: environment
        )
        let metadata = CachedConsumerTestMetadata(
            configurationContentHash: sha256Hex(configurationData),
            consumerSourcesHash: consumerConfigurationSourcesHash(consumerSources),
            testSourcesHash: consumerConfigurationSourcesHash(testSources)
        )
        let targetRoot = package.root.appendingPathComponent("Tests/\(consumerTestTargetName)")

        guard !cachedConsumerTestsAreCurrent(
            packageRoot: package.root,
            targetRoot: targetRoot,
            metadata: metadata,
            configurationData: configurationData,
            consumerSources: consumerSources,
            testSources: testSources
        ) else {
            return CachedConsumerTestPackage(
                package: package,
                testSourcesChanged: false
            )
        }

        try writeCachedConsumerTests(
            packageRoot: package.root,
            targetRoot: targetRoot,
            configurationData: configurationData,
            consumerSources: consumerSources,
            testSources: testSources,
            metadata: metadata
        )
        return CachedConsumerTestPackage(
            package: package,
            testSourcesChanged: true
        )
    }
}

private extension ConfigurationLoader {
    static let outputBeginMarker = "__BUMPER_OUTPUT_BEGIN__"
    static let outputEndMarker = "__BUMPER_OUTPUT_END__"
    static let configurationBuildTimeoutSeconds: TimeInterval = 600
    static let configurationCommandOutputLimitBytes = 4 * 1024 * 1024
    static let swiftToolchainIdentityTimeoutSeconds: TimeInterval = 10
    static let swiftToolchainIdentityOutputLimitBytes = 16 * 1024
    static let consumerPackageDirectory = ".bumper"
    static let consumerSourceDirectory = ".bumper/Sources"
    static let consumerTestDirectory = ".bumper/Tests"
    static let consumerRulePackageName = ".bumper"
    static let consumerRuleProductName = "BumperRules"
    static let consumerTestTargetName = "BumperRuleTests"
    static let configurationCacheEnvironmentKey = "BUMPER_CACHE_DIR"
    static let projectRunnerProductName = "BumperProjectRunner"
    static let consumerTestPlaceholder = "enum BumperGeneratedTestTargetPlaceholder {}\n"

    // shortcut: cache operations serialize in this process; use per-project locks if independent projects contend.
    static let projectCacheLock = NSLock()

    static func withProjectCacheLock<Value>(
        root: URL,
        environment: [String: String],
        operation: () throws -> Value
    ) throws -> Value {
        try projectCacheLock.withLock {
            let lockRoot = configurationCacheRoot(environment: environment).appendingPathComponent("Locks")
            try FileManager.default.createDirectory(at: lockRoot, withIntermediateDirectories: true)
            let identity = sha256Hex(Data(root.standardizedFileURL.path.utf8))
            let lockURL = lockRoot.appendingPathComponent("\(identity).project.lock")
            let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else {
                throw BumperError.consumerTestLockFailed(lockURL.path)
            }
            defer { _ = Darwin.close(descriptor) }
            var lock = flock(
                l_start: 0,
                l_len: 0,
                l_pid: 0,
                l_type: Int16(F_WRLCK),
                l_whence: Int16(SEEK_SET)
            )
            guard Darwin.fcntl(descriptor, F_SETLKW, &lock) == 0 else {
                throw BumperError.consumerTestLockFailed(lockURL.path)
            }
            defer {
                lock.l_type = Int16(F_UNLCK)
                _ = Darwin.fcntl(descriptor, F_SETLK, &lock)
            }
            return try operation()
        }
    }

    /// The configuration runner computes a pure value: it evaluates the
    /// repository's `BumperBowling.swift` into an `ArchitectureConfiguration`
    /// and prints it as JSON. It needs no repository access, no writable
    /// paths, and no network, so it runs under a deny-default Darwin sandbox
    /// (the same mechanism SwiftPM uses to evaluate `Package.swift`).
    static let sandboxProfile = """
    (version 1)
    (deny default)
    (import "system.sb")
    (deny network*)
    (allow process-exec)
    (allow file-read*)
    (allow sysctl-read)
    """

    static func runProjectRunner(root: URL, mode: ProjectRunnerMode, input: Data?) throws -> String {
        try withProjectCacheLock(root: root, environment: ProcessInfo.processInfo.environment) {
            let root = root.standardizedFileURL
            let configurationURL = root.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: configurationURL.path) else {
                throw BumperError.configurationMissing(configurationURL.path)
            }

            let packageRoot = try bumperPackageRoot()
            let cachedPackage = try makeCachedPackage(
                configurationURL: configurationURL,
                bumperPackageRoot: packageRoot
            )
            try buildCachedPackageIfNeeded(cachedPackage)

            let timeoutSeconds = try configurationEvaluationTimeout(
                environment: ProcessInfo.processInfo.environment
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = [
                "-p",
                sandboxProfile,
                cachedPackage.executableURL.path,
                mode.rawValue,
            ]
            process.environment = [:]

            let result = try runProcess(
                process,
                timeoutSeconds: timeoutSeconds,
                outputLimitBytes: configurationCommandOutputLimitBytes,
                stdin: input
            )

            if result.timedOut {
                throw BumperError.configurationExecutionTimedOut(
                    configurationURL.path,
                    Int(timeoutSeconds)
                )
            }

            if let stream = result.outputTooLargeStream {
                throw BumperError.configurationOutputTooLarge(
                    configurationURL.path,
                    stream,
                    configurationCommandOutputLimitBytes
                )
            }

            let stdoutText = try outputText(result.stdout, stream: "stdout")
            let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"

            guard result.terminationStatus == 0 else {
                throw BumperError.configurationExecutionFailed(
                    configurationURL.path,
                    stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            return try extractPayload(from: stdoutText)
        }
    }

}

extension ConfigurationLoader {
    static func runProcess(
        _ process: Process,
        timeoutSeconds: TimeInterval,
        outputLimitBytes: Int,
        stdin: Data? = nil
    ) throws -> CapturedProcessOutput {
        let stdout = Pipe()
        let stderr = Pipe()
        let stdinPipe = stdin.map { _ in Pipe() }
        var stdoutBuffer = BoundedOutputBuffer(limit: outputLimitBytes)
        var stderrBuffer = BoundedOutputBuffer(limit: outputLimitBytes)
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdinPipe

        let readHandles = [stdout.fileHandleForReading, stderr.fileHandleForReading]
        let handles = readHandles + (stdinPipe.map { [$0.fileHandleForWriting] } ?? [])
        for handle in handles {
            let flags = Darwin.fcntl(handle.fileDescriptor, F_GETFL)
            guard flags >= 0, Darwin.fcntl(handle.fileDescriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        if let stdinPipe {
            guard Darwin.fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        defer {
            for handle in handles { try? handle.close() }
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        try process.run()
        defer {
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        try? stdinPipe?.fileHandleForReading.close()
        var descriptors = readHandles.map { pollfd(fd: $0.fileDescriptor, events: Int16(POLLIN), revents: 0) }
        descriptors.append(pollfd(fd: stdinPipe?.fileHandleForWriting.fileDescriptor ?? -1, events: Int16(POLLOUT), revents: 0))
        var inputOffset = 0
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        var timedOut = false
        var outputTooLargeStream: String?

        while process.isRunning || descriptors.prefix(2).contains(where: { $0.fd >= 0 }) {
            if stdoutBuffer.hasExceededLimit || stderrBuffer.hasExceededLimit {
                outputTooLargeStream = stdoutBuffer.hasExceededLimit ? "stdout" : "stderr"
                break
            }
            let remaining = timeoutSeconds - startedAt.duration(to: clock.now).secondsValue
            guard remaining > 0 else {
                timedOut = true
                break
            }
            let wait = Int32(max(1, min(50, remaining * 1000)))
            let ready = Darwin.poll(&descriptors, nfds_t(descriptors.count), wait)
            if ready < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            for index in 0..<2 where descriptors[index].fd >= 0 && descriptors[index].revents != 0 {
                let count = Darwin.read(descriptors[index].fd, &bytes, bytes.count)
                if count > 0 {
                    let data = Data(bytes.prefix(count))
                    if index == 0 { stdoutBuffer.append(data) } else { stderrBuffer.append(data) }
                } else if count == 0 {
                    descriptors[index].fd = -1
                } else if errno != EAGAIN && errno != EINTR {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            if descriptors[2].fd >= 0, descriptors[2].revents != 0, let stdin {
                let count = stdin.withUnsafeBytes { buffer in
                    Darwin.write(descriptors[2].fd, buffer.baseAddress?.advanced(by: inputOffset), min(bytes.count, stdin.count - inputOffset))
                }
                if count >= 0 {
                    inputOffset += count
                } else if errno == EPIPE {
                    inputOffset = stdin.count
                } else if errno != EAGAIN && errno != EINTR {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            if descriptors[2].fd >= 0, inputOffset == stdin?.count || !process.isRunning {
                try? stdinPipe?.fileHandleForWriting.close()
                descriptors[2].fd = -1
            }
        }

        if process.isRunning {
            process.terminate()
            let terminationDeadline = clock.now.advanced(by: .seconds(5))
            while process.isRunning && clock.now < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        return CapturedProcessOutput(
            stdout: stdoutBuffer.data,
            stderr: stderrBuffer.data,
            terminationStatus: process.terminationStatus,
            timedOut: timedOut,
            outputTooLargeStream: outputTooLargeStream
        )
    }
}

private extension ConfigurationLoader {
    static func outputText(_ data: Data, stream: String) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw BumperError.configurationOutputMalformed("configuration \(stream) was not valid UTF-8")
        }
        return text
    }

    static func cachedPackageRoot(
        configurationURL: URL,
        bumperPackageRoot: URL,
        buildConfiguration: String,
        manifest: String,
        consumerSourcesHash: String,
        rulePackagesHash: String,
        cacheRoot: URL
    ) throws -> URL {
        let key = [
            "v4",
            projectRunnerProductName,
            buildConfiguration,
            configurationURL.standardizedFileURL.path,
            bumperPackageRoot.standardizedFileURL.path,
            try packageRootFingerprint(bumperPackageRoot),
            try swiftToolchainIdentity(),
            sha256Hex(Data(manifest.utf8)),
            sha256Hex(Data(runnerSource.utf8)),
            consumerSourcesHash,
            rulePackagesHash,
        ].joined(separator: "\n")

        let root = cacheRoot
            .appendingPathComponent(sha256Hex(Data(key.utf8)))
        return root
    }

    static func consumerConfigurationSources(root: URL) throws -> [ConsumerConfigurationSource] {
        try consumerSwiftSources(root: root, directory: consumerSourceDirectory)
    }

    static func consumerTestSources(root: URL) throws -> [ConsumerConfigurationSource] {
        try consumerSwiftSources(root: root, directory: consumerTestDirectory)
    }

    static func consumerSwiftSources(
        root: URL,
        directory: String
    ) throws -> [ConsumerConfigurationSource] {
        let sourceRoot = root.appendingPathComponent(directory)
        guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [ConsumerConfigurationSource] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true,
                  StringMatcher.suffix(".swift").matches(fileURL.lastPathComponent) else {
                continue
            }

            guard let relativePath = relativeSourcePath(of: fileURL, under: sourceRoot) else {
                throw BumperError.configurationOutputMalformed(
                    "consumer Swift source is outside its source root: \(fileURL.path)"
                )
            }
            guard !relativePath.isEmpty,
                  !relativePath.split(separator: "/").contains(where: isUnsafeRelativePathComponent) else {
                throw BumperError.configurationOutputMalformed(
                    "consumer Swift source has unsafe path: \(relativePath)"
                )
            }

            sources.append(
                ConsumerConfigurationSource(
                    relativePath: relativePath,
                    data: try Data(contentsOf: fileURL)
                )
            )
        }

        return sources.sorted { $0.relativePath < $1.relativePath }
    }

    static func consumerConfigurationSourcesHash(_ sources: [ConsumerConfigurationSource]) -> String {
        let payload = sources.map { source in
            source.relativePath + "\n" + sha256Hex(source.data)
        }.joined(separator: "\n")
        return sha256Hex(Data(payload.utf8))
    }

    static func isUnsafeRelativePathComponent(_ component: Substring) -> Bool {
        let value = String(component)
        return StringMatcher.exact(".").matches(value) || StringMatcher.exact("..").matches(value)
    }

    static func writeConsumerConfigurationSources(
        _ consumerSources: [ConsumerConfigurationSource],
        to destinationRoot: URL
    ) throws {
        guard !consumerSources.isEmpty else {
            return
        }

        for source in consumerSources {
            let destination = destinationRoot.appendingPathComponent(source.relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try source.data.write(to: destination, options: .atomic)
        }
    }

    static func cachedConsumerTestsAreCurrent(
        packageRoot: URL,
        targetRoot: URL,
        metadata: CachedConsumerTestMetadata,
        configurationData: Data,
        consumerSources: [ConsumerConfigurationSource],
        testSources: [ConsumerConfigurationSource]
    ) -> Bool {
        let metadataURL = packageRoot.appendingPathComponent(CachedConsumerTestMetadata.fileName)
        var expectedFiles = [
            "Placeholder.swift": Data(consumerTestPlaceholder.utf8),
            "Configuration/BumperBowling.swift": configurationData,
        ]
        for source in consumerSources {
            expectedFiles["ConsumerSources/\(source.relativePath)"] = source.data
        }
        for source in testSources {
            expectedFiles["ConsumerTests/\(source.relativePath)"] = source.data
        }

        guard let copiedFiles = cachedFileContents(in: targetRoot),
              copiedFiles == expectedFiles,
              let data = try? Data(contentsOf: metadataURL),
              let cached = try? JSONDecoder().decode(CachedConsumerTestMetadata.self, from: data) else {
            return false
        }
        return cached == metadata
    }

    static func cachedFileContents(in root: URL) -> [String: Data]? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else {
            return nil
        }

        var contents: [String: Data] = [:]
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else {
                return nil
            }
            guard values.isRegularFile == true else {
                continue
            }

            guard let relativePath = relativeSourcePath(of: fileURL, under: root),
                  !relativePath.isEmpty,
                  let data = try? Data(contentsOf: fileURL) else {
                return nil
            }
            contents[relativePath] = data
        }
        return contents
    }

    static func relativeSourcePath(of file: URL, under root: URL) -> String? {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let fileComponents = file.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              fileComponents.starts(with: rootComponents) else {
            return nil
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    static func writeCachedConsumerTests(
        packageRoot: URL,
        targetRoot: URL,
        configurationData: Data,
        consumerSources: [ConsumerConfigurationSource],
        testSources: [ConsumerConfigurationSource],
        metadata: CachedConsumerTestMetadata
    ) throws {
        let testsRoot = packageRoot.appendingPathComponent("Tests")
        let stagingRoot = testsRoot.appendingPathComponent(
            ".\(consumerTestTargetName)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        try consumerTestPlaceholder.write(
            to: stagingRoot.appendingPathComponent("Placeholder.swift"),
            atomically: true,
            encoding: .utf8
        )
        let configurationDestination = stagingRoot.appendingPathComponent("Configuration/BumperBowling.swift")
        try FileManager.default.createDirectory(
            at: configurationDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try configurationData.write(to: configurationDestination, options: .atomic)
        try writeConsumerConfigurationSources(
            consumerSources,
            to: stagingRoot.appendingPathComponent("ConsumerSources")
        )
        try writeConsumerConfigurationSources(
            testSources,
            to: stagingRoot.appendingPathComponent("ConsumerTests")
        )

        if FileManager.default.fileExists(atPath: targetRoot.path) {
            try FileManager.default.removeItem(at: targetRoot)
        }
        try FileManager.default.moveItem(at: stagingRoot, to: targetRoot)
        try JSONEncoder()
            .encode(metadata)
            .write(
                to: packageRoot.appendingPathComponent(CachedConsumerTestMetadata.fileName),
                options: .atomic
            )
    }

    static func rulePackageDependencies(root: URL) throws -> [RulePackageDependency] {
        let packageRoot = root.appendingPathComponent(consumerPackageDirectory).standardizedFileURL
        guard FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("Package.swift").path) else {
            return []
        }

        return [
            RulePackageDependency(
                path: packageRoot,
                package: consumerRulePackageName,
                product: consumerRuleProductName
            ),
        ]
    }

    static func rulePackageDependenciesHash(_ packages: [RulePackageDependency]) throws -> String {
        let payload = try packages.map { package in
            [
                package.path.path,
                package.package,
                package.product,
                try packageRootFingerprint(package.path),
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
        return sha256Hex(Data(payload.utf8))
    }

    static func buildCachedPackageIfNeeded(_ package: CachedPackage) throws {
        // SwiftPM also tracks resources and transitive package dependencies.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = cachedRunnerBuildArguments(
            packageRoot: package.root,
            buildConfiguration: package.buildConfiguration
        )

        let result = try runProcess(
            process,
            timeoutSeconds: configurationBuildTimeoutSeconds,
            outputLimitBytes: configurationCommandOutputLimitBytes
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                "\(package.productName) build",
                Int(configurationBuildTimeoutSeconds)
            )
        }

        if let stream = result.outputTooLargeStream {
            throw BumperError.configurationOutputTooLarge(
                "\(package.productName) build",
                stream,
                configurationCommandOutputLimitBytes
            )
        }

        let stdoutText = try outputText(result.stdout, stream: "build stdout")
        let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"
        guard result.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                "\(package.productName) build",
                [stdoutText, stderrText]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard FileManager.default.isExecutableFile(atPath: package.executableURL.path) else {
            throw BumperError.configurationOutputMalformed("\(package.productName) build did not produce an executable")
        }
    }

    static func cachedExecutableIsCurrent(_ executableURL: URL, metadataURL: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path),
              let executableValues = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let executableDate = executableValues.contentModificationDate,
              let metadataValues = try? metadataURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let metadataDate = metadataValues.contentModificationDate else {
            return false
        }
        return executableDate >= metadataDate
    }

    static func cachedPackageIsCurrent(
        root: URL,
        metadata: CachedPackageMetadata,
        manifest: String,
        configurationData: Data,
        consumerSources: [ConsumerConfigurationSource]
    ) -> Bool {
        let sources = root.appendingPathComponent("Sources/\(projectRunnerProductName)")
        var expectedSources = [
            "UserConfiguration.swift": configurationData,
            "main.swift": Data(runnerSource.utf8),
        ]
        for source in consumerSources {
            expectedSources["ConsumerSources/\(source.relativePath)"] = source.data
        }

        guard (try? Data(contentsOf: root.appendingPathComponent("Package.swift"))) == Data(manifest.utf8),
              cachedFileContents(in: sources) == expectedSources,
              let data = try? Data(contentsOf: root.appendingPathComponent(CachedPackageMetadata.fileName)),
              let existingMetadata = try? JSONDecoder().decode(CachedPackageMetadata.self, from: data) else {
            return false
        }

        return existingMetadata == metadata
    }

    static func swiftToolchainIdentity() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "--version"]

        let result = try runProcess(
            process,
            timeoutSeconds: swiftToolchainIdentityTimeoutSeconds,
            outputLimitBytes: swiftToolchainIdentityOutputLimitBytes
        )

        if result.timedOut {
            throw BumperError.configurationExecutionTimedOut(
                "swift --version",
                Int(swiftToolchainIdentityTimeoutSeconds)
            )
        }

        if let stream = result.outputTooLargeStream {
            throw BumperError.configurationOutputTooLarge(
                "swift --version",
                stream,
                swiftToolchainIdentityOutputLimitBytes
            )
        }

        let stderrText = String(data: result.stderr, encoding: .utf8) ?? "<non-UTF-8 stderr>"
        guard result.terminationStatus == 0 else {
            throw BumperError.configurationExecutionFailed(
                "swift --version",
                stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return try outputText(result.stdout, stream: "swift --version")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func packageRootFingerprint(_ root: URL) throws -> String {
        let fileManager = FileManager.default
        let roots = [
            root.appendingPathComponent("Package.swift"),
            root.appendingPathComponent("Sources"),
        ]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var entries: [String] = []

        for rootURL in roots {
            if let values = try? rootURL.resourceValues(forKeys: keys),
               values.isRegularFile == true {
                entries.append(fingerprintEntry(for: rootURL, packageRoot: root, values: values))
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard StringMatcher.exact("swift").matches(fileURL.pathExtension),
                      let values = try? fileURL.resourceValues(forKeys: keys),
                      values.isRegularFile == true else {
                    continue
                }

                entries.append(fingerprintEntry(for: fileURL, packageRoot: root, values: values))
            }
        }

        return sha256Hex(Data(entries.sorted().joined(separator: "\n").utf8))
    }

    static func fingerprintEntry(
        for fileURL: URL,
        packageRoot: URL,
        values: URLResourceValues
    ) -> String {
        let relativePath = fileURL.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(relativePath):\(values.fileSize ?? 0):\(modifiedAt)"
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func bumperPackageRoot() throws -> URL {
        if let environmentPath = ProcessInfo.processInfo.environment["BUMPER_PACKAGE_PATH"] {
            let root = URL(fileURLWithPath: environmentPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
                throw BumperError.configurationPackageUnavailable(root.path)
            }
            return root
        }

        let sourcePath = URL(fileURLWithPath: #filePath)
        let root = sourcePath
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) else {
            throw BumperError.configurationPackageUnavailable(root.path)
        }
        return root
    }

    static func packageManifest(
        bumperPackageRoot: URL,
        rulePackages: [RulePackageDependency],
        runnerProductName: String
    ) -> String {
        let dependencyEntries = ([
            ".package(name: \"BumperBowling\", path: \(swiftStringLiteral(bumperPackageRoot.path)))",
            ".package(url: \"https://github.com/swiftlang/swift-syntax.git\", from: \"602.0.0\")",
        ] + rulePackages.map { package in
            ".package(path: \(swiftStringLiteral(package.path.path)))"
        }).joined(separator: ",\n                ")
        let targetDependencies = ([
            ".product(name: \"BumperBowlingCore\", package: \"BumperBowling\")",
            ".product(name: \"SwiftParser\", package: \"swift-syntax\")",
            ".product(name: \"SwiftSyntax\", package: \"swift-syntax\")",
        ] + rulePackages.map { package in
            ".product(name: \(swiftStringLiteral(package.product)), package: \(swiftStringLiteral(package.package)))"
        }).joined(separator: ",\n                        ")
        let testTargetDependencies = ([
            ".product(name: \"BumperBowlingCore\", package: \"BumperBowling\")",
            ".product(name: \"BumperBowlingTestSupport\", package: \"BumperBowling\")",
            ".product(name: \"SwiftParser\", package: \"swift-syntax\")",
            ".product(name: \"SwiftSyntax\", package: \"swift-syntax\")",
        ] + rulePackages.map { package in
            ".product(name: \(swiftStringLiteral(package.product)), package: \(swiftStringLiteral(package.package)))"
        }).joined(separator: ",\n                        ")

        return """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "BumperConfigurationLoader",
            platforms: [
                .macOS(.v15),
            ],
            dependencies: [
                \(dependencyEntries),
            ],
            targets: [
                .executableTarget(
                    name: \(swiftStringLiteral(runnerProductName)),
                    dependencies: [
                        \(targetDependencies),
                    ],
                    swiftSettings: [
                        .swiftLanguageMode(.v6),
                    ]
                ),
                .testTarget(
                    name: \(swiftStringLiteral(consumerTestTargetName)),
                    dependencies: [
                        \(testTargetDependencies),
                    ],
                    swiftSettings: [
                        .swiftLanguageMode(.v6),
                    ]
                ),
            ]
        )
        """
    }

    /// One runner, two modes. `describe` prints the project's serializable
    /// configuration; `evaluate` reads a bounded `RepositoryInput` from stdin
    /// and prints one `RuleReport`. Both reference the project's `bumper`
    /// entry point.
    static var runnerSource: String {
        """
        import BumperBowlingCore
        import Foundation

        do {
            let mode = CommandLine.arguments.dropFirst().first ?? "describe"
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let payloadData: Data
            switch mode {
            case "describe":
                payloadData = try encoder.encode(bumper.architecture)
            case "evaluate":
                let inputData = FileHandle.standardInput.readDataToEndOfFile()
                let input = try JSONDecoder().decode(RepositoryInput.self, from: inputData)
                payloadData = try encoder.encode(bumper.evaluationRun(input))
            default:
                FileHandle.standardError.write(Data(("unknown runner mode: " + mode + "\\n").utf8))
                exit(64)
            }
            let payload = String(data: payloadData, encoding: .utf8) ?? "{}"
            let output = "\(outputBeginMarker)\\n" + payload + "\\n\(outputEndMarker)\\n"
            FileHandle.standardOutput.write(Data(output.utf8))
        } catch {
            FileHandle.standardError.write(Data((String(describing: error) + "\\n").utf8))
            exit(1)
        }
        """
    }

    static func swiftStringLiteral(_ value: String) -> String {
        value.debugDescription
    }

    static func extractPayload(from output: String) throws -> String {
        guard let begin = output.range(of: outputBeginMarker),
              let end = output.range(of: outputEndMarker, range: begin.upperBound..<output.endIndex) else {
            throw BumperError.configurationOutputMalformed(output)
        }

        var payload = String(output[begin.upperBound..<end.lowerBound])
        if StringMatcher.prefix("\n").matches(payload) {
            payload.removeFirst()
        }
        if StringMatcher.suffix("\n").matches(payload) {
            payload.removeLast()
        }
        return payload
    }
}

extension ConfigurationLoader {
    static func configurationCacheRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let environmentPath = environment[configurationCacheEnvironmentKey],
           !environmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: environmentPath).standardizedFileURL
        }

        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BumperConfigurationLoaderCache")
            .standardizedFileURL
    }
}

struct CapturedProcessOutput {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32
    let timedOut: Bool
    let outputTooLargeStream: String?
}

struct CachedPackageMetadata: Codable, Equatable {
    static let fileName = ".bumper-cache.json"

    let configurationContentHash: String
    let consumerSourcesHash: String
    let rulePackagesHash: String
    let runnerProductName: String
    let buildConfiguration: String
}

struct CachedPackage {
    let root: URL
    let executableURL: URL
    let productName: String
    let buildConfiguration: String
    let needsBuild: Bool
}

struct CachedConsumerTestPackage {
    let package: CachedPackage
    let testSourcesChanged: Bool
}

struct CachedConsumerTestMetadata: Codable, Equatable {
    static let fileName = ".bumper-tests.json"

    let configurationContentHash: String
    let consumerSourcesHash: String
    let testSourcesHash: String
}

private struct ConsumerConfigurationSource {
    let relativePath: String
    let data: Data
}

private struct RulePackageDependency {
    let path: URL
    let package: String
    let product: String
}

private struct BoundedOutputBuffer {
    private let limit: Int
    private(set) var data = Data()
    private(set) var hasExceededLimit = false

    init(limit: Int) {
        self.limit = Swift.max(1, limit)
    }

    mutating func append(_ chunk: Data) {
        guard !hasExceededLimit else { return }
        let remaining = limit - data.count
        data.append(contentsOf: chunk.prefix(remaining))
        hasExceededLimit = chunk.count > remaining
    }
}
