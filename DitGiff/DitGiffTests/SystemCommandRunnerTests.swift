import Foundation
import Testing

@testable import DitGiff

/// Real processes on purpose: a deadlocked pipe or a working directory that never took
/// effect only show up against a real `Process`. No `git` and no repository needed.
nonisolated struct SystemCommandRunnerTests {
    private let runner = SystemCommandRunner()

    @Test func runsAnAbsolutePathAndCapturesStandardOutput() async throws {
        let output = try await runner.run(
            CommandRequest(executable: "/bin/echo", arguments: ["hello"])
        )

        #expect(output.standardOutput == "hello\n")
        #expect(output.standardError.isEmpty)
        #expect(output.exitCode == 0)
        #expect(output.didSucceed)
    }

    @Test func resolvesABareNameThroughPath() async throws {
        let output = try await runner.run(
            CommandRequest(executable: "echo", arguments: ["resolved"])
        )

        #expect(output.standardOutput == "resolved\n")
    }

    @Test func reportsANonZeroExitAsOutputRatherThanThrowing() async throws {
        let output = try await runner.run(CommandRequest(executable: "/usr/bin/false"))

        #expect(output.exitCode == 1)
        #expect(output.didSucceed == false)
    }

    @Test func capturesStandardErrorSeparately() async throws {
        let missingPath = "/dit-giff-no-such-path"
        let output = try await runner.run(
            CommandRequest(executable: "/bin/ls", arguments: [missingPath])
        )

        #expect(output.didSucceed == false)
        #expect(output.standardOutput.isEmpty)
        #expect(output.standardError.contains(missingPath))
    }

    @Test func runsInTheRequestedWorkingDirectory() async throws {
        // /tmp is a symlink to /private/tmp, and pwd answers with the resolved path.
        let directory = URL(fileURLWithPath: "/private/tmp")

        let output = try await runner.run(
            CommandRequest(executable: "/bin/pwd", workingDirectory: directory)
        )

        #expect(output.standardOutput == "/private/tmp\n")
    }

    @Test func mergesTheRequestEnvironmentOverTheInheritedOne() async throws {
        let output = try await runner.run(
            CommandRequest(
                executable: "/usr/bin/env",
                environment: ["DIT_GIFF_SEAM_CHECK": "present"]
            )
        )

        #expect(output.standardOutput.contains("DIT_GIFF_SEAM_CHECK=present"))
        // The inherited environment survives the merge.
        #expect(output.standardOutput.contains("PATH="))
    }

    /// A naive read-then-wait hangs forever on output this size.
    @Test func readsOutputLargerThanThePipeBufferWithoutDeadlocking() async throws {
        let lineCount = 20_000
        let line = String(repeating: "x", count: 40)
        let contents = String(repeating: line + "\n", count: lineCount)

        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dit-giff-large-\(UUID().uuidString).txt")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let output = try await runner.run(
            CommandRequest(executable: "/bin/cat", arguments: [file.path])
        )

        #expect(output.standardOutput.count == contents.count)
        #expect(output.didSucceed)
    }

    @Test func throwsWhenTheExecutableIsNotOnPath() async {
        let thrown = await #expect(throws: CommandFailure.self) {
            _ = try await runner.run(CommandRequest(executable: "dit-giff-no-such-binary"))
        }

        guard case let .launchFailed(executable, _)? = thrown else {
            Issue.record("expected a launch failure, got \(String(describing: thrown))")
            return
        }
        #expect(executable == "dit-giff-no-such-binary")
    }

    @Test func throwsWhenAnAbsolutePathIsNotExecutable() async {
        let thrown = await #expect(throws: CommandFailure.self) {
            _ = try await runner.run(CommandRequest(executable: "/etc/hosts"))
        }

        guard case .launchFailed? = thrown else {
            Issue.record("expected a launch failure, got \(String(describing: thrown))")
            return
        }
    }
}
