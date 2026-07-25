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

    /// Proves the child is gone — not that Swift merely stopped awaiting.
    @Test func cancellingALongRunningCommandTerminatesTheProcess() async throws {
        let pidFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dit-giff-cancel-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let script = """
        echo $$ > '\(pidFile.path)'
        exec /bin/sleep 120
        """
        let task = Task {
            try await runner.run(
                CommandRequest(executable: "/bin/sh", arguments: ["-c", script])
            )
        }

        let pid = try await waitForPID(in: pidFile)
        #expect(processExists(pid))

        task.cancel()
        let thrown = await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(thrown != nil)

        try await waitUntilProcessExits(pid)
        #expect(processExists(pid) == false)
    }

    @Test func cancellingAfterTheCommandAlreadyFinishedDoesNotBreak() async throws {
        let output = try await runner.run(
            CommandRequest(executable: "/bin/echo", arguments: ["done"])
        )
        #expect(output.standardOutput == "done\n")
        #expect(output.didSucceed)

        // A finished run has nothing left to terminate. Starting and immediately
        // cancelling a no-op that exits at once must not crash or invent a failure
        // for an already-reaped process either.
        let quick = Task {
            try await runner.run(CommandRequest(executable: "/usr/bin/true"))
        }
        // Let it finish first, then cancel the completed task.
        let quickOutput = try await quick.value
        quick.cancel()
        #expect(quickOutput.didSucceed)
    }

    @Test func manyCancelledRunsDoNotExhaustResources() async throws {
        let iterations = 40
        for _ in 0..<iterations {
            let pidFile = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("dit-giff-cancel-loop-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: pidFile) }

            let script = """
            echo $$ > '\(pidFile.path)'
            exec /bin/sleep 60
            """
            let task = Task {
                try await runner.run(
                    CommandRequest(executable: "/bin/sh", arguments: ["-c", script])
                )
            }
            let pid = try await waitForPID(in: pidFile)
            task.cancel()
            _ = try? await task.value
            try await waitUntilProcessExits(pid)
            #expect(processExists(pid) == false)
        }

        // Still able to spawn and read after the storm — pipes and FDs did not leak
        // into a broken runner.
        let output = try await runner.run(
            CommandRequest(executable: "/bin/echo", arguments: ["still-ok"])
        )
        #expect(output.standardOutput == "still-ok\n")
    }

    // MARK: - Process liveness

    private func waitForPID(
        in file: URL,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws -> pid_t {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let contents = try? String(contentsOf: file, encoding: .utf8) {
                let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Int32(trimmed), value > 0 {
                    return value
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for child pid file at \(file.path)")
        return -1
    }

    private func waitUntilProcessExits(
        _ pid: pid_t,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while processExists(pid) {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                Issue.record("Timed out waiting for pid \(pid) to exit after cancel")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func processExists(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        // kill(pid, 0) probes liveness without signalling. ESRCH means gone.
        return kill(pid, 0) == 0
    }
}

