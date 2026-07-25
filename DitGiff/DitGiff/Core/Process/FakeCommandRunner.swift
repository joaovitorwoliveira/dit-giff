import Foundation

/// Answers from a table of canned output. It sits in the app target rather than the
/// test target so SwiftUI previews can use it too — a preview cannot import tests.
///
/// An `actor` because it records what it was asked to run, and that is mutable state
/// reached from several tasks. The cost is an `await` on its properties.
actor FakeCommandRunner: CommandRunner {
    nonisolated enum Failure: Error, Equatable, LocalizedError {
        case noStub(CommandInvocation)

        var errorDescription: String? {
            switch self {
            case let .noStub(invocation):
                "FakeCommandRunner has no stub for `\([invocation.executable] + invocation.arguments)`"
            }
        }
    }

    private enum StreamStub {
        case events([CommandStreamEvent])
        case failure(CommandFailure)
    }

    private var responses: [CommandInvocation: Result<CommandOutput, CommandFailure>] = [:]
    private var streamResponses: [CommandInvocation: StreamStub] = [:]
    private(set) var receivedRequests: [CommandRequest] = []

    init() {}

    func stub(
        _ executable: String,
        _ arguments: [String] = [],
        standardOutput: String = "",
        standardError: String = "",
        exitCode: Int32 = 0
    ) {
        let output = CommandOutput(
            standardOutput: standardOutput,
            standardError: standardError,
            exitCode: exitCode
        )
        responses[CommandInvocation(executable: executable, arguments: arguments)] = .success(output)
    }

    func stubFailure(_ executable: String, _ arguments: [String] = [], _ failure: CommandFailure) {
        responses[CommandInvocation(executable: executable, arguments: arguments)] = .failure(failure)
    }

    func stubStream(
        _ executable: String,
        _ arguments: [String] = [],
        events: [CommandStreamEvent]
    ) {
        streamResponses[CommandInvocation(executable: executable, arguments: arguments)] = .events(events)
    }

    func stubStreamFailure(
        _ executable: String,
        _ arguments: [String] = [],
        _ failure: CommandFailure
    ) {
        streamResponses[CommandInvocation(executable: executable, arguments: arguments)] = .failure(failure)
    }

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        // Same cooperative cancel as SystemCommandRunner: a cancelled task does not
        // get a canned success back as if the command had finished.
        try Task.checkCancellation()
        receivedRequests.append(request)

        // Raised instead of guessing: an unstubbed command is a gap in the test, and
        // returning empty output would hide it.
        guard let response = responses[request.invocation] else {
            throw Failure.noStub(request.invocation)
        }
        try Task.checkCancellation()
        return try response.get()
    }

    // nonisolated so the protocol witness stays synchronous; actor state is reached
    // from the producer task below.
    nonisolated func stream(
        _ request: CommandRequest
    ) -> AsyncThrowingStream<CommandStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events = try await self.streamEvents(for: request)
                    for event in events {
                        try Task.checkCancellation()
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func streamEvents(for request: CommandRequest) throws -> [CommandStreamEvent] {
        try Task.checkCancellation()
        receivedRequests.append(request)

        guard let stub = streamResponses[request.invocation] else {
            throw Failure.noStub(request.invocation)
        }
        try Task.checkCancellation()

        switch stub {
        case let .events(events):
            return events
        case let .failure(failure):
            throw failure
        }
    }
}
