import Foundation
import Testing

@testable import DitGiff

/// Real processes on purpose: streaming deadlocks and cancel-vs-zombie only show up
/// against a live `Process`. Mirrors `SystemCommandRunnerTests` style.
nonisolated struct CommandStreamTests {
    private let runner = SystemCommandRunner()

    @Test func streamsOutputLargerThanThePipeBufferWithoutDeadlocking() async throws {
        let lineCount = 20_000
        let line = String(repeating: "x", count: 40)
        let contents = String(repeating: line + "\n", count: lineCount)

        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dit-giff-stream-large-\(UUID().uuidString).txt")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let events = try await collect(
            runner.stream(CommandRequest(executable: "/bin/cat", arguments: [file.path]))
        )

        let outputLines = events.compactMap { event -> String? in
            if case let .standardOutputLine(line) = event { return line }
            return nil
        }
        #expect(outputLines.count == lineCount)
        #expect(outputLines.allSatisfy { $0 == line })
        #expect(events.last == .exited(code: 0))
    }

    @Test func emitsAFinalLineWithoutATrailingNewline() async throws {
        let events = try await collect(
            runner.stream(
                CommandRequest(executable: "/bin/sh", arguments: ["-c", "printf 'no-newline'"])
            )
        )

        #expect(events == [
            .standardOutputLine("no-newline"),
            .exited(code: 0),
        ])
    }

    @Test func deliversStdoutAndStderrOnTheirOwnCases() async throws {
        let script = "echo out1; echo err1 >&2; echo out2; echo err2 >&2"
        let events = try await collect(
            runner.stream(CommandRequest(executable: "/bin/sh", arguments: ["-c", script]))
        )

        let stdout = events.compactMap { event -> String? in
            if case let .standardOutputLine(line) = event { return line }
            return nil
        }
        let stderr = events.compactMap { event -> String? in
            if case let .standardErrorLine(line) = event { return line }
            return nil
        }

        #expect(stdout == ["out1", "out2"])
        #expect(stderr == ["err1", "err2"])
        #expect(events.last == .exited(code: 0))
    }

    @Test func exitedIsLastEvenWhenTheChildFails() async throws {
        let events = try await collect(
            runner.stream(CommandRequest(executable: "/usr/bin/false"))
        )

        #expect(events == [.exited(code: 1)])
    }

    /// Proves the child is gone. Cancelling the iterating task terminates the
    /// stream (onTermination → ProcessControl) without necessarily throwing
    /// CancellationError from `task.value` — AsyncThrowingStream ends the
    /// `for try await` loop cleanly on cancel (Swift concurrency behavior).
    @Test func cancellingAStreamTerminatesTheProcess() async throws {
        let pidFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dit-giff-stream-cancel-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }

        let script = """
        echo $$ > '\(pidFile.path)'
        exec /bin/sleep 120
        """
        let task = Task {
            try await collect(
                runner.stream(
                    CommandRequest(executable: "/bin/sh", arguments: ["-c", script])
                )
            )
        }

        let pid = try await waitForPID(in: pidFile)
        #expect(processExists(pid))

        task.cancel()
        _ = try? await task.value

        try await waitUntilProcessExits(pid)
        #expect(processExists(pid) == false)
    }

    @Test func standardInputReachesTheChild() async throws {
        let events = try await collect(
            runner.stream(
                CommandRequest(executable: "/bin/cat", standardInput: "via-stdin\n")
            )
        )

        #expect(events == [
            .standardOutputLine("via-stdin"),
            .exited(code: 0),
        ])
    }

    @Test func missingBinaryFailsTheStreamWithLaunchFailed() async {
        let thrown = await #expect(throws: CommandFailure.self) {
            _ = try await collect(
                runner.stream(CommandRequest(executable: "dit-giff-no-such-binary"))
            )
        }

        guard case let .launchFailed(executable, _)? = thrown else {
            Issue.record("expected a launch failure, got \(String(describing: thrown))")
            return
        }
        #expect(executable == "dit-giff-no-such-binary")
    }

    @Test func fakeStubsAStreamSequence() async throws {
        let fake = FakeCommandRunner()
        await fake.stubStream(
            "claude",
            ["-p"],
            events: [
                .standardOutputLine(#"{"type":"assistant"}"#),
                .standardErrorLine("hint"),
                .exited(code: 0),
            ]
        )

        let events = try await collect(
            fake.stream(CommandRequest(executable: "claude", arguments: ["-p"]))
        )

        #expect(events == [
            .standardOutputLine(#"{"type":"assistant"}"#),
            .standardErrorLine("hint"),
            .exited(code: 0),
        ])

        let received = await fake.receivedRequests
        #expect(received.map(\.invocation) == [
            CommandInvocation(executable: "claude", arguments: ["-p"]),
        ])
    }

    @Test func fakeStreamFailureIsDeliveredAsAStreamError() async {
        let fake = FakeCommandRunner()
        let failure = CommandFailure.launchFailed(executable: "claude", reason: "not found")
        await fake.stubStreamFailure("claude", [], failure)

        let thrown = await #expect(throws: CommandFailure.self) {
            _ = try await collect(fake.stream(CommandRequest(executable: "claude")))
        }
        #expect(thrown == failure)
    }

    // MARK: - Helpers

    private func collect(
        _ stream: AsyncThrowingStream<CommandStreamEvent, Error>
    ) async throws -> [CommandStreamEvent] {
        var events: [CommandStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

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
        return kill(pid, 0) == 0
    }
}
