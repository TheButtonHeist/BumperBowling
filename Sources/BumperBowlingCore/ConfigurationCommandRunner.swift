import Darwin
import Foundation

enum ConfigurationLoader {
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
            terminationReason: process.terminationReason,
            timedOut: timedOut,
            outputTooLargeStream: outputTooLargeStream
        )
    }
}

struct CapturedProcessOutput {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32
    let terminationReason: Process.TerminationReason
    let timedOut: Bool
    let outputTooLargeStream: String?
}

private extension Duration {
    var secondsValue: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
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

extension ConfigurationLoader {
    static let sandboxProfile = """
    (version 1)
    (deny default)
    (import "system.sb")
    (deny network*)
    (allow process-exec)
    (allow file-read*)
    (allow sysctl-read)
    """

    static func runPackage(root: URL) throws -> Int32 {
        let package = try BumperCommands.packageRoot(root)
        let configuration = ProcessInfo.processInfo.environment["BUMPER_RUNNER_BUILD_CONFIGURATION"] ?? "debug"
        guard ["debug", "release"].contains(configuration) else {
            throw BumperError("BUMPER_RUNNER_BUILD_CONFIGURATION must be debug or release.")
        }
        let timeoutValue = ProcessInfo.processInfo.environment["BUMPER_EVALUATION_TIMEOUT_SECONDS"] ?? "60"
        guard let timeout = Double(timeoutValue), timeout > 0, timeout.isFinite else {
            throw BumperError("BUMPER_EVALUATION_TIMEOUT_SECONDS must be positive finite seconds.")
        }
        let arguments = ["--package-path", package.path, "--configuration", configuration]
        let build = try swift(["build"] + arguments + ["--product", "BumperRulesRunner"], at: root, timeout: 600)
        guard build.terminationStatus == 0 else {
            throw BumperError("Rule package build failed with status \(build.terminationStatus).")
        }
        let pathResult = try swift(["build"] + arguments + ["--show-bin-path"], at: root, timeout: 10, forwardOutput: false)
        guard pathResult.terminationStatus == 0,
              let binPath = String(data: pathResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              binPath.hasPrefix("/"), !binPath.contains("\n") else {
            throw BumperError("SwiftPM did not return an executable directory.")
        }
        let lookup = Process()
        lookup.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        lookup.arguments = ["--find", "swift"]
        let lookupResult = try capture(lookup, timeout: 10, forwardOutput: false)
        guard lookupResult.terminationStatus == 0,
              let swiftPath = String(data: lookupResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              swiftPath.hasSuffix("/usr/bin/swift") else {
            throw BumperError("Could not locate the selected Swift toolchain.")
        }
        let toolchain = URL(fileURLWithPath: swiftPath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = URL(fileURLWithPath: binPath).appendingPathComponent("BumperRulesRunner")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", sandboxProfile, executable.path, root.standardizedFileURL.path]
        // SourceKitten needs the toolchain's library path even for syntax-only rules.
        process.environment = ["TOOLCHAIN_DIR": toolchain.path]
        process.currentDirectoryURL = root
        let result = try capture(process, timeout: timeout)
        guard result.terminationReason == .exit, result.terminationStatus == 0 || result.terminationStatus == 1 || result.terminationStatus == 2 else {
            throw BumperError("Rule executable failed with status \(result.terminationStatus).")
        }
        return result.terminationStatus
    }

    private static func swift(
        _ arguments: [String], at root: URL, timeout: Double, forwardOutput: Bool = true
    ) throws -> CapturedProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments
        process.currentDirectoryURL = root
        return try capture(process, timeout: timeout, forwardOutput: forwardOutput)
    }

    private static func capture(_ process: Process, timeout: Double, forwardOutput: Bool = true) throws -> CapturedProcessOutput {
        let result = try runProcess(process, timeoutSeconds: timeout, outputLimitBytes: 4 * 1024 * 1024)
        if forwardOutput { FileHandle.standardOutput.write(result.stdout) }
        FileHandle.standardError.write(result.stderr)
        guard !result.timedOut else { throw BumperError("Rule command timed out after \(timeout) seconds.") }
        guard result.outputTooLargeStream == nil else { throw BumperError("Rule command exceeded the 4 MiB output limit.") }
        return result
    }

    static func runSwiftTests(packageRoot: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "test", "--package-path", packageRoot.path]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
