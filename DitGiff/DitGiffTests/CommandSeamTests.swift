import Foundation
import Testing

@testable import DitGiff

nonisolated struct CommandSeamTests {

    // MARK: - CommandOutput

    @Test func nonZeroExitIsAnAnswerAndNotAFailure() {
        let output = CommandOutput(standardOutput: "", standardError: "", exitCode: 1)

        #expect(output.didSucceed == false)
    }

    @Test func requireSuccessReturnsStandardOutput() throws {
        let request = CommandRequest(executable: "git", arguments: ["status"])
        let output = CommandOutput(standardOutput: "clean\n")

        #expect(try output.requireSuccess(for: request) == "clean\n")
    }

    @Test func requireSuccessReportsTheCommandAndItsStandardError() {
        let request = CommandRequest(executable: "git", arguments: ["diff", "main...topic"])
        let output = CommandOutput(
            standardError: "fatal: bad revision 'main...topic'\n",
            exitCode: 128
        )

        let thrown = #expect(throws: CommandFailure.self) {
            _ = try output.requireSuccess(for: request)
        }

        #expect(thrown == .exitedWithFailure(request: request, output: output))

        let message = thrown?.errorDescription ?? ""
        #expect(message.contains("git diff main...topic"))
        #expect(message.contains("128"))
        #expect(message.contains("bad revision"))
    }

    @Test func invocationIgnoresWhereTheCommandRan() {
        let inOneRepository = CommandRequest(
            executable: "git",
            arguments: ["branch"],
            workingDirectory: URL(fileURLWithPath: "/tmp/a")
        )
        let inAnother = CommandRequest(
            executable: "git",
            arguments: ["branch"],
            workingDirectory: URL(fileURLWithPath: "/tmp/b")
        )

        #expect(inOneRepository.invocation == inAnother.invocation)
    }

    // MARK: - FakeCommandRunner

    @Test func fakeReturnsTheStubbedOutput() async throws {
        let runner = FakeCommandRunner()
        await runner.stub("git", ["rev-parse", "--abbrev-ref", "HEAD"], standardOutput: "main\n")

        let output = try await runner.run(
            CommandRequest(executable: "git", arguments: ["rev-parse", "--abbrev-ref", "HEAD"])
        )

        #expect(output.standardOutput == "main\n")
        #expect(output.didSucceed)
    }

    @Test func fakeMatchesAStubRegardlessOfWorkingDirectory() async throws {
        let runner = FakeCommandRunner()
        await runner.stub("git", ["branch"], standardOutput: "main\ntopic\n")

        let output = try await runner.run(
            CommandRequest(
                executable: "git",
                arguments: ["branch"],
                workingDirectory: URL(fileURLWithPath: "/tmp/somewhere")
            )
        )

        #expect(output.standardOutput == "main\ntopic\n")
    }

    @Test func fakeRecordsWhatItWasAskedToRunInOrder() async throws {
        let runner = FakeCommandRunner()
        await runner.stub("git", ["branch"])
        await runner.stub("git", ["diff"], standardOutput: "diff --git a/x b/x\n")

        _ = try await runner.run(CommandRequest(executable: "git", arguments: ["branch"]))
        _ = try await runner.run(
            CommandRequest(
                executable: "git",
                arguments: ["diff"],
                workingDirectory: URL(fileURLWithPath: "/tmp/repo")
            )
        )

        let received = await runner.receivedRequests
        #expect(received.map(\.arguments) == [["branch"], ["diff"]])
        #expect(received.last?.workingDirectory == URL(fileURLWithPath: "/tmp/repo"))
    }

    @Test func fakeRefusesToInventOutputForAnUnstubbedCommand() async {
        let runner = FakeCommandRunner()
        let request = CommandRequest(executable: "git", arguments: ["log"])

        let thrown = await #expect(throws: FakeCommandRunner.Failure.self) {
            _ = try await runner.run(request)
        }

        #expect(thrown == .noStub(request.invocation))
    }

    @Test func fakeCanStubACommandThatNeverLaunches() async {
        let runner = FakeCommandRunner()
        let failure = CommandFailure.launchFailed(executable: "claude", reason: "not found in PATH")
        await runner.stubFailure("claude", ["-p"], failure)

        let thrown = await #expect(throws: CommandFailure.self) {
            _ = try await runner.run(CommandRequest(executable: "claude", arguments: ["-p"]))
        }

        #expect(thrown == failure)
    }
}
