import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Bounded process I/O")
struct ProcessRunnerTests {
    @Test(arguments: [false, true])
    func timeoutCoversBlockedInputAndInheritedOutput(blockedInput: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", blockedInput ? "sleep 1; cat >/dev/null" : "sleep 1 &"]
        let result = try ConfigurationLoader.runProcess(
            process,
            timeoutSeconds: 0.1,
            outputLimitBytes: 1024,
            stdin: blockedInput ? Data(repeating: 65, count: 1024 * 1024) : nil
        )
        #expect(result.timedOut)
    }

    @Test
    func capturesLargeInputAndBothOutputStreams() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "cat; printf diagnostic >&2"]
        let input = Data(repeating: 65, count: 3 * 1024 * 1024)
        let result = try ConfigurationLoader.runProcess(process, timeoutSeconds: 5, outputLimitBytes: input.count, stdin: input)
        #expect(result.stdout == input)
        #expect(result.stderr == Data("diagnostic".utf8))
        #expect(result.terminationStatus == 0)
        #expect(!result.timedOut)
        #expect(result.outputTooLargeStream == nil)
    }

    @Test(arguments: [false, true])
    func outputLimitRemainsBounded(stderr: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while :; do printf '0123456789'; done" + (stderr ? " >&2" : "")]
        let result = try ConfigurationLoader.runProcess(process, timeoutSeconds: 5, outputLimitBytes: 100)
        #expect(result.outputTooLargeStream == (stderr ? "stderr" : "stdout"))
        #expect((stderr ? result.stderr : result.stdout).count == 100)
        #expect(!result.timedOut)
    }

    @Test
    func childExitingBeforeReadingInputDoesNotCrashHost() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/false")
        let result = try ConfigurationLoader.runProcess(process, timeoutSeconds: 5, outputLimitBytes: 1024, stdin: Data(repeating: 65, count: 1024 * 1024))
        #expect(result.terminationStatus != 0)
        #expect(!result.timedOut)
    }
}
