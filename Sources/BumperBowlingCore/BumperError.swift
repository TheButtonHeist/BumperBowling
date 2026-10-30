import Foundation

public enum BumperError: Error, CustomStringConvertible {
    case configurationAlreadyExists(String)
    case configurationExecutionFailed(String, String)
    case configurationExecutionTimedOut(String, Int)
    case configurationMissing(String)
    case configurationOutputTooLarge(String, String, Int)
    case configurationOutputMalformed(String)
    case configurationPackageUnavailable(String)
    case consumerTestLockFailed(String)
    case consumerTestsMissing(String)
    case invalidEvaluationTimeout(String)
    case invalidRunnerBuildConfiguration(String)
    case noComponentForFile(String)
    case repositoryScanLimitExceeded(String)
    case sourceFileOutsideRoot(String, String)
    case sourceFileTooLarge(String, UInt64, UInt64)
    case unsupportedLanguage(String)
    case unreadableFile(String)
    case unsafeSymlinkedSourceFile(String)

    public var description: String {
        switch self {
        case .configurationAlreadyExists(let path):
            "Configuration already exists at \(path)."
        case .configurationExecutionFailed(let path, let message):
            "Failed to execute configuration at \(path): \(message)"
        case .configurationExecutionTimedOut(let path, let seconds):
            "Timed out after \(seconds) seconds while executing configuration at \(path)."
        case .configurationMissing(let path):
            "No BumperBowling.swift configuration found at \(path). Run `bumper init` first."
        case .configurationOutputTooLarge(let path, let stream, let limit):
            "Configuration at \(path) wrote more than \(limit) bytes to \(stream)."
        case .configurationOutputMalformed(let message):
            "Configuration runner produced malformed output: \(message)"
        case .configurationPackageUnavailable(let path):
            "Could not locate the BumperBowling package at \(path). Set BUMPER_PACKAGE_PATH to the package root."
        case .consumerTestLockFailed(let path):
            "Could not acquire the project cache lock at \(path)."
        case .consumerTestsMissing(let path):
            "No consumer rule tests found under \(path). Add Swift tests under .bumper/Tests."
        case .invalidEvaluationTimeout(let value):
            "BUMPER_EVALUATION_TIMEOUT_SECONDS must be a positive, finite number of seconds; found '\(value)'."
        case .invalidRunnerBuildConfiguration(let value):
            "BUMPER_RUNNER_BUILD_CONFIGURATION must be 'release' or 'debug'; found '\(value)'."
        case .noComponentForFile(let path):
            "No component matches \(path)."
        case .repositoryScanLimitExceeded(let message):
            "Repository scan limit exceeded: \(message)"
        case .sourceFileOutsideRoot(let path, let root):
            "Refusing to scan source file outside repository root \(root): \(path)"
        case .sourceFileTooLarge(let path, let size, let limit):
            "Refusing to scan \(path) because it is \(size) bytes; limit is \(limit) bytes."
        case .unsupportedLanguage(let path):
            "Only Swift source files are supported: \(path)."
        case .unreadableFile(let path):
            "Could not read source file at \(path)."
        case .unsafeSymlinkedSourceFile(let path):
            "Refusing to scan symlinked Swift source file: \(path)"
        }
    }
}
