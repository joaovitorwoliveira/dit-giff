import Foundation

/// The only adapter that knows Claude Code's CLI flags, auth probe, and NDJSON shape.
nonisolated struct ClaudeCodeDiffAgent: DiffAgent {
    private let runner: any CommandRunner
    private let binaryLocator: any ClaudeBinaryLocating
    private let silenceTimeout: Duration
    private let silenceTimeoutSeconds: Int

    init(
        runner: any CommandRunner,
        binaryLocator: any ClaudeBinaryLocating,
        silenceTimeoutSeconds: Int = 60
    ) {
        self.runner = runner
        self.binaryLocator = binaryLocator
        self.silenceTimeoutSeconds = silenceTimeoutSeconds
        self.silenceTimeout = .seconds(silenceTimeoutSeconds)
    }

    func explainFile(_ request: AgentExplainRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
            do {
                let claudePath = try await binaryLocator.locateClaudeExecutable()
                try await ensureLoggedIn(claudePath: claudePath)

                let commandRequest = Self.explainCommandRequest(
                    claudePath: claudePath,
                    request: request
                )
                try await consumeExplainStream(
                    runner.stream(commandRequest),
                    yield: { continuation.yield($0) }
                )
                continuation.finish()
            } catch is CancellationError {
                // Consumer cancelled the stream — end quietly, same contract as CommandRunner.
                continuation.finish()
            } catch let error as AgentError {
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(
                    throwing: AgentError.failed(reason: error.localizedDescription)
                )
            }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Invocation (flags verified by spike — do not change)

    static func explainArguments(model: AgentModel, effort: AgentEffort) -> [String] {
        [
            "-p",
            "--output-format", "stream-json",
            "--include-partial-messages",
            "--verbose",
            "--safe-mode",
            "--no-session-persistence",
            "--tools", "Bash",
            "--permission-mode", "dontAsk",
            "--allowedTools",
            "Bash(git diff:*)",
            "Bash(git show:*)",
            "Bash(git log:*)",
            "Bash(git status:*)",
            "Bash(git merge-base:*)",
            "Bash(git ls-files:*)",
            "--model", model.cliValue,
            "--effort", effort.cliValue,
        ]
    }

    static func explainCommandRequest(
        claudePath: String,
        request: AgentExplainRequest
    ) -> CommandRequest {
        CommandRequest(
            executable: claudePath,
            arguments: explainArguments(model: request.model, effort: request.effort),
            workingDirectory: request.repositoryRoot,
            standardInput: prompt(for: request)
        )
    }

    static func prompt(for request: AgentExplainRequest) -> String {
        """
        File: \(request.filePath)
        Comparing: \(request.baseName)...\(request.compareName)

        Patch for this file:
        \(request.patch)

        This is a quick file explain — keep the whole reply short enough to read without scrolling.

        Write one short paragraph on what changed. Then at most three short clues — pick only the ones that matter; do not list everything you notice. Phrase each clue as an observation or a question, never as a verdict. The human decides.

        Stay inside this patch. Do not explore the rest of the repository unless the patch alone is not enough to say what changed.
        """
    }

    static let authStatusArguments = ["auth", "status", "--json"]

    // MARK: - Auth

    private func ensureLoggedIn(claudePath: String) async throws {
        let output: CommandOutput
        do {
            output = try await runner.run(
                CommandRequest(
                    executable: claudePath,
                    arguments: Self.authStatusArguments
                )
            )
        } catch let failure as CommandFailure {
            throw AgentError.failed(reason: failure.localizedDescription)
        }

        guard output.didSucceed else {
            let detail = output.standardError.isEmpty
                ? output.standardOutput
                : output.standardError
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentError.failed(
                reason: trimmed.isEmpty
                    ? "claude auth status failed with exit code \(output.exitCode)."
                    : trimmed
            )
        }

        let payload = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payload.data(using: .utf8) else {
            throw AgentError.failed(reason: "claude auth status returned non-UTF8 output.")
        }

        let status: AuthStatusPayload
        do {
            status = try JSONDecoder().decode(AuthStatusPayload.self, from: data)
        } catch {
            throw AgentError.failed(reason: "claude auth status returned unexpected JSON.")
        }

        guard status.loggedIn else {
            throw AgentError.notLoggedIn
        }
    }

    // MARK: - Stream translation

    private func consumeExplainStream(
        _ commandStream: AsyncThrowingStream<CommandStreamEvent, Error>,
        yield: @escaping @Sendable (AgentEvent) -> Void
    ) async throws {
        let bridge = CommandEventBridge()
        let silenceTimeout = self.silenceTimeout
        let silenceTimeoutSeconds = self.silenceTimeoutSeconds

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await event in commandStream {
                        try Task.checkCancellation()
                        await bridge.publish(event)
                    }
                    await bridge.finish()
                } catch is CancellationError {
                    await bridge.finish()
                } catch {
                    await bridge.fail(error)
                }
            }

            do {
                var apiRetryCount = 0
                var receivedResult = false

                while true {
                    try Task.checkCancellation()
                    let event = try await bridge.next(
                        silenceTimeout: silenceTimeout,
                        silenceTimeoutSeconds: silenceTimeoutSeconds
                    )
                    guard let event else {
                        // Success is the `result` event, never stream end alone — a
                        // cancelled or truncated run must not look like a complete answer.
                        if receivedResult { break }
                        throw AgentError.failed(
                            reason: "Claude Code ended without a result event."
                        )
                    }

                    switch event {
                    case let .standardOutputLine(line):
                        try handleStandardOutputLine(
                            line,
                            apiRetryCount: &apiRetryCount,
                            receivedResult: &receivedResult,
                            yield: yield
                        )
                        if receivedResult { break }
                    case .standardErrorLine, .exited:
                        continue
                    }
                }
            } catch {
                group.cancelAll()
                // Already failing on the translator path — sibling CancellationError is
                // only cleanup from cancelAll. Real stream failures arrived earlier via
                // bridge.fail → bridge.next, not as a leftover sibling result here.
                while await group.nextResult() != nil {}
                throw error
            }

            // Done translating — stop the process reader. Its CancellationError is the
            // expected cancelAll signal: the producer never fails the task group with a
            // real error (those go through bridge.fail and were already handled above),
            // so draining cannot turn a yielded `.finished` into a quiet cancel.
            group.cancelAll()
            while let result = await group.nextResult() {
                if case let .failure(error) = result, !(error is CancellationError) {
                    throw error
                }
            }
        }
    }

    private func handleStandardOutputLine(
        _ line: String,
        apiRetryCount: inout Int,
        receivedResult: inout Bool,
        yield: @Sendable (AgentEvent) -> Void
    ) throws {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let data = trimmed.data(using: .utf8) else { return }

        let envelope: NDJSONEnvelope
        do {
            envelope = try JSONDecoder().decode(NDJSONEnvelope.self, from: data)
        } catch {
            // Malformed lines happen mid-stream; skipping them must not invent success.
            return
        }

        switch envelope.type {
        case "stream_event":
            if let text = envelope.event?.textDelta {
                yield(.textDelta(text))
            }

        case "assistant":
            for command in envelope.message?.toolCommands ?? [] {
                yield(.toolStarted(command: command))
            }

        case "system":
            if envelope.subtype == "api_retry" {
                apiRetryCount += 1
                if apiRetryCount >= 2 {
                    throw AgentError.noNetwork
                }
            }

        case "result":
            receivedResult = true
            if envelope.is_error == true {
                let reason = envelope.result?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let reason, !reason.isEmpty {
                    throw AgentError.failed(reason: reason)
                }
                throw AgentError.failed(reason: "Claude Code reported an error.")
            }
            yield(.finished)

        default:
            break
        }
    }
}

// MARK: - Silence-aware bridge

/// Hands process events from the producer task to the translator with a per-wait
/// silence deadline. An actor so the two tasks never share an AsyncIterator.
private actor CommandEventBridge {
    private enum State {
        case open
        case finished
        case failed(Error)
    }

    private var state: State = .open
    private var pending: [CommandStreamEvent] = []
    private var waiter: CheckedContinuation<CommandStreamEvent?, Error>?

    func publish(_ event: CommandStreamEvent) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: event)
            return
        }
        pending.append(event)
    }

    func finish() {
        state = .finished
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: nil)
        }
    }

    func fail(_ error: Error) {
        state = .failed(error)
        if let waiter {
            self.waiter = nil
            waiter.resume(throwing: error)
        }
    }

    func next(
        silenceTimeout: Duration,
        silenceTimeoutSeconds: Int
    ) async throws -> CommandStreamEvent? {
        if let immediate = try dequeueOrTerminal() {
            return immediate
        }

        return try await withThrowingTaskGroup(of: CommandStreamEvent?.self) { group in
            group.addTask {
                try await self.waitForEvent()
            }
            group.addTask {
                try await Task.sleep(for: silenceTimeout)
                throw AgentError.timedOut(afterSeconds: silenceTimeoutSeconds)
            }

            do {
                guard let settled = try await group.next() else {
                    group.cancelAll()
                    while await group.nextResult() != nil {}
                    return nil
                }
                // Winner already chosen. cancelAll makes the loser throw CancellationError;
                // a racing silence timeout after an event must not override it — the event
                // ended the silence. Drain so we do not leave a sibling task stranded.
                group.cancelAll()
                while await group.nextResult() != nil {}
                return settled
            } catch {
                group.cancelAll()
                while await group.nextResult() != nil {}
                throw error
            }
        }
    }

    private func dequeueOrTerminal() throws -> CommandStreamEvent?? {
        if !pending.isEmpty {
            return pending.removeFirst()
        }
        switch state {
        case .finished:
            return .some(nil)
        case let .failed(error):
            throw error
        case .open:
            return nil
        }
    }

    private func waitForEvent() async throws -> CommandStreamEvent? {
        if let immediate = try dequeueOrTerminal() {
            return immediate
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
            }
        } onCancel: {
            Task { await self.resumeWaiterForCancellation() }
        }
    }

    private func resumeWaiterForCancellation() {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(throwing: CancellationError())
    }
}

// MARK: - NDJSON decoding

private nonisolated struct AuthStatusPayload: Decodable, Sendable {
    let loggedIn: Bool
}

private nonisolated struct NDJSONEnvelope: Decodable, Sendable {
    let type: String
    let subtype: String?
    let is_error: Bool?
    let result: String?
    let event: NDJSONStreamEvent?
    let message: NDJSONAssistantMessage?
}

private nonisolated struct NDJSONStreamEvent: Decodable, Sendable {
    let type: String
    let delta: NDJSONDelta?

    var textDelta: String? {
        guard type == "content_block_delta",
              delta?.type == "text_delta",
              let text = delta?.text
        else {
            return nil
        }
        return text
    }
}

private nonisolated struct NDJSONDelta: Decodable, Sendable {
    let type: String
    let text: String?
}

private nonisolated struct NDJSONAssistantMessage: Decodable, Sendable {
    let content: [NDJSONContentBlock]?

    var toolCommands: [String] {
        guard let content else { return [] }
        return content.compactMap { block in
            guard block.type == "tool_use" else { return nil }
            let command = block.input?.command?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let command, !command.isEmpty else { return nil }
            return command
        }
    }
}

private nonisolated struct NDJSONContentBlock: Decodable, Sendable {
    let type: String
    let input: NDJSONToolInput?
}

private nonisolated struct NDJSONToolInput: Decodable, Sendable {
    let command: String?
}
