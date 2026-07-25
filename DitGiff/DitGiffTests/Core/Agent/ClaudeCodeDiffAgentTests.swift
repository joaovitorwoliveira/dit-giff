import Foundation
import Testing

@testable import DitGiff

nonisolated struct ClaudeCodeDiffAgentTests {
    private let fakeClaudePath = "/tmp/dit-giff-fake-claude"
    private let repoRoot = URL(fileURLWithPath: "/tmp/dit-giff-repo", isDirectory: true)

    // MARK: - NDJSON → AgentEvent

    @Test func baselineNDJSONEmitsTextDeltasInOrderThenFinished() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.baselineSuccess)

        let events = try await collect(agent(runner: runner).explainFile(sampleRequest()))

        #expect(events == [
            .textDelta("Este repositório"),
            .textDelta(" é uma pequena utilidade em Swift (`Calculator.swift`) com funções para validar idade, c"),
            .textDelta("umprimentar por nome e somar uma lista de valores."),
            .finished,
        ])
    }

    @Test func assistantTextDoesNotDuplicateStreamEventDeltas() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.baselineSuccess)

        let events = try await collect(agent(runner: runner).explainFile(sampleRequest()))
        let deltas = events.compactMap { event -> String? in
            if case let .textDelta(text) = event { return text }
            return nil
        }

        #expect(deltas.count == 3)
        #expect(deltas.joined() == "Este repositório é uma pequena utilidade em Swift (`Calculator.swift`) com funções para validar idade, cumprimentar por nome e somar uma lista de valores.")
        #expect(events.contains(.finished))
    }

    @Test func toolUseBecomesToolStartedWithTheCommand() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.toolsThenText)

        let events = try await collect(agent(runner: runner).explainFile(sampleRequest()))

        #expect(events.first == .toolStarted(command: "git diff main...feature"))
        #expect(events.contains(.textDelta("O")))
        #expect(events.last == .finished)
    }

    @Test func secondApiRetryBecomesNoNetworkWithoutWaitingForTen() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.networkRetries)

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await collect(agent(runner: runner).explainFile(sampleRequest()))
        }
        #expect(thrown == .noNetwork)
    }

    @Test func resultWithIsErrorBecomesFailed() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.resultError)

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await collect(agent(runner: runner).explainFile(sampleRequest()))
        }
        #expect(
            thrown == .failed(reason: "API Error: Unable to connect to API (ConnectionRefused)")
        )
    }

    @Test func streamWithoutResultNeverSucceeds() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.missingResult)

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await collect(agent(runner: runner).explainFile(sampleRequest()))
        }
        guard case let .failed(reason)? = thrown else {
            Issue.record("expected failed, got \(String(describing: thrown))")
            return
        }
        #expect(reason.contains("without a result event"))
    }

    @Test func invalidJSONLineDoesNotFailTheCall() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.invalidJSONInTheMiddle)

        let events = try await collect(agent(runner: runner).explainFile(sampleRequest()))

        #expect(events == [
            .textDelta("before"),
            .textDelta(" after"),
            .finished,
        ])
    }

    // MARK: - Auth / binary / timeout / flags

    @Test func loggedOutAuthStatusDoesNotStartTheExplainCall() async throws {
        let runner = FakeCommandRunner()
        await runner.stub(
            fakeClaudePath,
            ClaudeCodeDiffAgent.authStatusArguments,
            standardOutput: #"{"loggedIn":false,"authMethod":"none"}"#
        )

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await collect(agent(runner: runner).explainFile(sampleRequest()))
        }
        #expect(thrown == .notLoggedIn)

        let received = await runner.receivedRequests
        #expect(received.count == 1)
        #expect(received[0].arguments == ClaudeCodeDiffAgent.authStatusArguments)
        #expect(!received.contains(where: { $0.arguments.contains("-p") }))
    }

    @Test func missingBinaryBecomesClaudeNotFound() async throws {
        let runner = FakeCommandRunner()
        let searched = ["/no/claude", "/also/missing/claude"]
        let agent = ClaudeCodeDiffAgent(
            runner: runner,
            binaryLocator: FixedClaudeBinaryLocator(notFoundSearchedPaths: searched)
        )

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await collect(agent.explainFile(sampleRequest()))
        }
        #expect(thrown == .claudeNotFound(searchedPaths: searched))

        let received = await runner.receivedRequests
        #expect(received.isEmpty)
    }

    @Test func prolongedSilenceBecomesTimedOut() async throws {
        let runner = HungAfterAuthCommandRunner(claudePath: fakeClaudePath)
        let agent = ClaudeCodeDiffAgent(
            runner: runner,
            binaryLocator: FixedClaudeBinaryLocator(path: fakeClaudePath),
            silenceTimeoutSeconds: 1
        )

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await collect(agent.explainFile(sampleRequest()))
        }
        #expect(thrown == .timedOut(afterSeconds: 1))
    }

    @Test func explainArgumentsKeepTheSecurityBoundaryFlags() {
        let arguments = ClaudeCodeDiffAgent.explainArguments(model: .sonnet, effort: .high)

        #expect(arguments.contains("--safe-mode"))
        #expect(arguments.contains("--permission-mode"))
        let permissionIndex = arguments.firstIndex(of: "--permission-mode")
        #expect(permissionIndex.map { arguments[arguments.index(after: $0)] } == "dontAsk")

        #expect(arguments.contains("--allowedTools"))
        for tool in [
            "Bash(git diff:*)",
            "Bash(git show:*)",
            "Bash(git log:*)",
            "Bash(git status:*)",
            "Bash(git merge-base:*)",
            "Bash(git ls-files:*)",
        ] {
            #expect(arguments.contains(tool), "missing allowed tool \(tool)")
        }

        #expect(!arguments.contains("--disallowedTools"))
    }

    @Test func explainRequestWiresStdinPromptWorkingDirectoryAndFlags() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.baselineSuccess)

        let request = sampleRequest()
        _ = try await collect(agent(runner: runner).explainFile(request))

        let received = await runner.receivedRequests
        let explain = try #require(received.first(where: { $0.arguments.contains("-p") }))
        #expect(explain.executable == fakeClaudePath)
        #expect(explain.workingDirectory == repoRoot)
        #expect(explain.standardInput == ClaudeCodeDiffAgent.prompt(for: request))
        #expect(explain.arguments.contains("--safe-mode"))
        #expect(explain.arguments.contains("dontAsk"))
        #expect(explain.arguments.contains("--model"))
        #expect(explain.arguments.contains("sonnet"))
        #expect(explain.arguments.contains("--effort"))
        #expect(explain.arguments.contains("high"))
    }

    // MARK: - Cancel vs successful finish

    @Test func successfulResultEmitsFinishedAndDoesNotSurfaceCancellation() async throws {
        let runner = FakeCommandRunner()
        try await stubLoggedIn(runner)
        try await stubExplainStream(runner, ndjson: ClaudeNDJSONFixtures.baselineSuccess)

        // collect() returning proves cancelAll on the process-reader sibling did not
        // rethrow CancellationError after a successful `result`.
        let events = try await collect(agent(runner: runner).explainFile(sampleRequest()))

        #expect(events.contains(.finished))
        #expect(events.last == .finished)
    }

    @Test func cancellingAfterPartialOutputNeverEmitsFinished() async throws {
        let partialLine = ClaudeNDJSONFixtures.streamEvents(
            from: ClaudeNDJSONFixtures.baselineSuccess
        ).compactMap { event -> String? in
            if case let .standardOutputLine(line) = event { return line }
            return nil
        }.first { line in
            line.contains("stream_event") && line.contains("text_delta")
        }
        let line = try #require(partialLine)

        let runner = PartialThenHangCommandRunner(
            claudePath: fakeClaudePath,
            partialOutputLine: line
        )
        let agent = ClaudeCodeDiffAgent(
            runner: runner,
            binaryLocator: FixedClaudeBinaryLocator(path: fakeClaudePath)
        )

        let probe = ExplainEventProbe()
        let consumer = Task {
            do {
                for try await event in agent.explainFile(sampleRequest()) {
                    await probe.append(event)
                }
            } catch {
                // Consumer-task cancel surfaces as CancellationError here even when
                // the agent stream itself finished without throwing.
            }
        }

        for _ in 0..<100 {
            if await probe.sawTextDelta { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await probe.sawTextDelta)

        consumer.cancel()
        _ = await consumer.result
        let events = await probe.events

        #expect(!events.contains(.finished))
    }

    // MARK: - Harness

    private func agent(runner: FakeCommandRunner) -> ClaudeCodeDiffAgent {
        ClaudeCodeDiffAgent(
            runner: runner,
            binaryLocator: FixedClaudeBinaryLocator(path: fakeClaudePath)
        )
    }

    private func sampleRequest() -> AgentExplainRequest {
        AgentExplainRequest(
            repositoryRoot: repoRoot,
            filePath: "Calculator.swift",
            patch: "@@ -1 +1 @@\n-old\n+new\n",
            baseName: "main",
            compareName: "feature",
            model: .sonnet,
            effort: .high
        )
    }

    private func stubLoggedIn(_ runner: FakeCommandRunner) async throws {
        await runner.stub(
            fakeClaudePath,
            ClaudeCodeDiffAgent.authStatusArguments,
            standardOutput: #"{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"pro"}"#
        )
    }

    private func stubExplainStream(_ runner: FakeCommandRunner, ndjson: String) async throws {
        let request = sampleRequest()
        let arguments = ClaudeCodeDiffAgent.explainArguments(
            model: request.model,
            effort: request.effort
        )
        await runner.stubStream(
            fakeClaudePath,
            arguments,
            events: ClaudeNDJSONFixtures.streamEvents(from: ndjson)
        )
    }

    private func collect(
        _ stream: AsyncThrowingStream<AgentEvent, Error>
    ) async throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

/// Returns a fixed path or `.claudeNotFound`. Lives in tests so production code stays lean.
private struct FixedClaudeBinaryLocator: ClaudeBinaryLocating {
    let path: String?
    let searchedPaths: [String]

    init(path: String) {
        self.path = path
        self.searchedPaths = []
    }

    init(notFoundSearchedPaths: [String]) {
        self.path = nil
        self.searchedPaths = notFoundSearchedPaths
    }

    func locateClaudeExecutable() async throws -> String {
        guard let path else {
            throw AgentError.claudeNotFound(searchedPaths: searchedPaths)
        }
        return path
    }
}

/// Auth succeeds; the explain stream then stays silent so the silence deadline can fire.
private struct HungAfterAuthCommandRunner: CommandRunner {
    let claudePath: String

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        guard request.executable == claudePath,
              request.arguments == ClaudeCodeDiffAgent.authStatusArguments
        else {
            throw FakeCommandRunner.Failure.noStub(request.invocation)
        }
        return CommandOutput(
            standardOutput: #"{"loggedIn":true,"authMethod":"claude.ai"}"#
        )
    }

    nonisolated func stream(
        _ request: CommandRequest
    ) -> AsyncThrowingStream<CommandStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try await Task.sleep(for: .seconds(3600))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

/// One text delta, then hangs until the stream is cancelled — for cancel-vs-finished tests.
private struct PartialThenHangCommandRunner: CommandRunner {
    let claudePath: String
    let partialOutputLine: String

    func run(_ request: CommandRequest) async throws -> CommandOutput {
        guard request.executable == claudePath,
              request.arguments == ClaudeCodeDiffAgent.authStatusArguments
        else {
            throw FakeCommandRunner.Failure.noStub(request.invocation)
        }
        return CommandOutput(
            standardOutput: #"{"loggedIn":true,"authMethod":"claude.ai"}"#
        )
    }

    nonisolated func stream(
        _ request: CommandRequest
    ) -> AsyncThrowingStream<CommandStreamEvent, Error> {
        let line = partialOutputLine
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.standardOutputLine(line))
                try await Task.sleep(for: .seconds(3600))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private actor ExplainEventProbe {
    private(set) var events: [AgentEvent] = []
    private(set) var sawTextDelta = false

    func append(_ event: AgentEvent) {
        events.append(event)
        if case .textDelta = event {
            sawTextDelta = true
        }
    }
}
