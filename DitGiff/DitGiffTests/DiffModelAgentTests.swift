import Foundation
import Testing

@testable import DitGiff

/// Live `DiffModel` + injected `DiffAgent`: streaming, queue, cache, mapping, errors.
@MainActor
struct DiffModelAgentTests {

    // MARK: - Fake agent

    private final class FakeDiffAgent: DiffAgent, @unchecked Sendable {
        private let lock = NSLock()
        private var scripted: [[AgentEvent]] = []
        private var scriptedErrors: [AgentError?] = []
        private var scriptIndex = 0
        private(set) var requests: [AgentExplainRequest] = []

        /// Parks the Nth explain (0-based) until `releasePark` — for queue tests.
        private var parkCallIndex: Int?
        private var parkContinuation: CheckedContinuation<Void, Never>?
        private var startedContinuation: CheckedContinuation<Void, Never>?

        /// After yielding this many events (1-based), park until `releaseMidStreamPark`.
        private var pauseAfterYieldedCount: Int?
        private var midStreamParkContinuation: CheckedContinuation<Void, Never>?
        private var midStreamStartedContinuation: CheckedContinuation<Void, Never>?

        func enqueue(events: [AgentEvent], error: AgentError? = nil) {
            lock.lock()
            scripted.append(events)
            scriptedErrors.append(error)
            lock.unlock()
        }

        func parkCall(at index: Int) {
            lock.lock()
            parkCallIndex = index
            lock.unlock()
        }

        func pauseAfterYielding(_ count: Int) {
            lock.lock()
            pauseAfterYieldedCount = count
            lock.unlock()
        }

        func waitUntilParkStarts() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if parkContinuation != nil {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                startedContinuation = continuation
                lock.unlock()
            }
        }

        func waitUntilMidStreamPark() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if midStreamParkContinuation != nil {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                midStreamStartedContinuation = continuation
                lock.unlock()
            }
        }

        func releasePark() {
            lock.lock()
            let continuation = parkContinuation
            parkContinuation = nil
            lock.unlock()
            continuation?.resume()
        }

        func releaseMidStreamPark() {
            lock.lock()
            let continuation = midStreamParkContinuation
            midStreamParkContinuation = nil
            lock.unlock()
            continuation?.resume()
        }

        var requestCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return requests.count
        }

        func request(at index: Int) -> AgentExplainRequest? {
            lock.lock()
            defer { lock.unlock() }
            guard requests.indices.contains(index) else { return nil }
            return requests[index]
        }

        func explainFile(
            _ request: AgentExplainRequest
        ) -> AsyncThrowingStream<AgentEvent, Error> {
            lock.lock()
            requests.append(request)
            let callIndex = requests.count - 1
            let events: [AgentEvent]
            let error: AgentError?
            if scriptIndex < scripted.count {
                events = scripted[scriptIndex]
                error = scriptedErrors[scriptIndex]
                scriptIndex += 1
            } else {
                events = [.textDelta("unexpected"), .finished]
                error = nil
            }
            let shouldPark = parkCallIndex == callIndex
            let pauseAfter = pauseAfterYieldedCount
            lock.unlock()

            return AsyncThrowingStream { continuation in
                let task = Task {
                    if shouldPark {
                        self.lock.lock()
                        let started = self.startedContinuation
                        self.startedContinuation = nil
                        self.lock.unlock()
                        started?.resume()

                        await withCheckedContinuation { (park: CheckedContinuation<Void, Never>) in
                            self.lock.lock()
                            self.parkContinuation = park
                            self.lock.unlock()
                        }
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                    }

                    var yielded = 0
                    for event in events {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        continuation.yield(event)
                        yielded += 1
                        if pauseAfter == yielded {
                            self.lock.lock()
                            let started = self.midStreamStartedContinuation
                            self.midStreamStartedContinuation = nil
                            self.lock.unlock()
                            started?.resume()

                            await withCheckedContinuation { (park: CheckedContinuation<Void, Never>) in
                                self.lock.lock()
                                self.midStreamParkContinuation = park
                                self.lock.unlock()
                            }
                            if Task.isCancelled {
                                continuation.finish()
                                return
                            }
                        }
                    }
                    if let error {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish()
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    task.cancel()
                }
            }
        }
    }

    // MARK: - Harness

    private func session(
        displayName: String = "billing-service",
        baseName: String = "main",
        compareName: String = "feature"
    ) -> DiffSession {
        DiffSession(
            repository: GitRepository(
                rootURL: URL(fileURLWithPath: "/repo/\(displayName)", isDirectory: true),
                displayName: displayName,
                head: .branch(compareName)
            ),
            base: GitBranch(
                name: baseName,
                fullRef: "refs/heads/\(baseName)",
                remote: nil
            ),
            compare: GitBranch(
                name: compareName,
                fullRef: "refs/heads/\(compareName)",
                remote: nil
            ),
            goal: "",
            attachedSpecName: nil
        )
    }

    private func stubSuccessfulPatch(
        on runner: FakeCommandRunner,
        session: DiffSession,
        files: [(path: String, body: String)]
    ) async {
        let range = "\(session.base.fullRef)...\(session.compare.fullRef)"
        var unifiedParts: [String] = []
        var rawParts: [String] = []
        for file in files {
            unifiedParts.append(
                """
                diff --git a/\(file.path) b/\(file.path)
                index d95f3ad..5ea2ed4 100644
                --- a/\(file.path)
                +++ b/\(file.path)
                \(file.body)
                """
            )
            rawParts.append(":100644 100644 d95f3ad 5ea2ed4 M\0\(file.path)\0")
        }
        let unified = unifiedParts.joined(separator: "")
        let raw = rawParts.joined()

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", session.base.fullRef],
            standardOutput: "abc\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", session.compare.fullRef],
            standardOutput: "def\n"
        )
        await runner.stub(
            "git",
            GitService.unifiedDiffArguments(range: range),
            standardOutput: unified
        )
        await runner.stub(
            "git",
            GitService.rawDiffArguments(range: range),
            standardOutput: raw
        )
    }

    private func stubBinaryAndTextPatch(
        on runner: FakeCommandRunner,
        session: DiffSession
    ) async {
        let range = "\(session.base.fullRef)...\(session.compare.fullRef)"
        let textPath = "Sources/Text.swift"
        let binaryPath = "Assets/icon.png"
        let unified = """
            diff --git a/\(textPath) b/\(textPath)
            index d95f3ad..5ea2ed4 100644
            --- a/\(textPath)
            +++ b/\(textPath)
            @@ -1 +1 @@
            -old
            +new
            diff --git a/\(binaryPath) b/\(binaryPath)
            new file mode 100644
            index 0000000..abcdef1
            Binary files /dev/null and b/\(binaryPath) differ
            """
        let raw =
            ":100644 100644 d95f3ad 5ea2ed4 M\0\(textPath)\0"
            + ":000000 100644 0000000 abcdef1 A\0\(binaryPath)\0"

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", session.base.fullRef],
            standardOutput: "abc\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", session.compare.fullRef],
            standardOutput: "def\n"
        )
        await runner.stub(
            "git",
            GitService.unifiedDiffArguments(range: range),
            standardOutput: unified
        )
        await runner.stub(
            "git",
            GitService.rawDiffArguments(range: range),
            standardOutput: raw
        )
    }

    private func loadModel(
        agent: FakeDiffAgent,
        files: [(path: String, body: String)] = [
            (path: "Sources/A.swift", body: "@@ -1 +1 @@\n-old\n+new\n")
        ]
    ) async throws -> (DiffModel, DiffSession) {
        let runner = FakeCommandRunner()
        let session = session()
        await stubSuccessfulPatch(on: runner, session: session, files: files)
        let model = DiffModel(git: GitService(runner: runner), agent: agent)
        model.load(session)
        await model.pendingLoad?.value
        #expect(model.loadState == .loaded)
        return (model, session)
    }

    @Test func loadingANewSessionClearsTheChatThreadFromThePreviousBranch() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [
            .textDelta("explanation about branch A"),
            .finished,
        ])
        let runner = FakeCommandRunner()
        let first = session(compareName: "feature-a")
        let second = session(compareName: "feature-b")
        await stubSuccessfulPatch(
            on: runner,
            session: first,
            files: [(path: "Sources/A.swift", body: "@@ -1 +1 @@\n-old\n+new\n")]
        )
        await stubSuccessfulPatch(
            on: runner,
            session: second,
            files: [(path: "Sources/B.swift", body: "@@ -1 +1 @@\n-x\n+y\n")]
        )

        let model = DiffModel(git: GitService(runner: runner), agent: agent)
        model.load(first)
        await model.pendingLoad?.value
        let file = try #require(model.files.first)
        model.explainFile(file)
        await model.pendingExplain?.value

        #expect(model.isChatOpen)
        #expect(model.thread?.messages.last?.text == "explanation about branch A")

        model.load(second)
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)

        await model.pendingLoad?.value
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)
        #expect(model.compareBranch == "feature-b")
    }

    // MARK: - Streaming

    @Test func explainFileConcatenatesDeltasInOrderAndPresentsTheFinishedReply() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [
            .textDelta("First "),
            .textDelta("second "),
            .textDelta("third."),
            .finished,
        ])
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        #expect(model.canExplainFile(file))
        model.explainFile(file)
        #expect(model.isChatOpen)
        #expect(model.isThinking)
        await model.pendingExplain?.value

        #expect(model.isThinking == false)
        let reply = try #require(model.thread?.messages.last)
        #expect(reply.role == .agent)
        #expect(reply.text == "First second third.")
        #expect(reply.location == "A.swift")
        #expect(agent.requestCount == 1)
    }

    @Test func aStreamWithoutFinishedIsNotCachedAsACompleteExplanation() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("partial only")])
        agent.enqueue(events: [.textDelta("complete"), .finished])
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        model.explainFile(file)
        await model.pendingExplain?.value

        #expect(agent.requestCount == 1)
        // Not treated as complete: asking again issues a new agent call.
        model.explainFile(file)
        await model.pendingExplain?.value

        #expect(agent.requestCount == 2)
        #expect(model.thread?.messages.last?.text == "complete")
    }

    @Test func aStreamWithoutFinishedDoesNotLeavePartialProseAsTheAnswer() async throws {
        let agent = FakeDiffAgent()
        let partial =
            "this is correct for the common case, but when the input is null—"
        agent.enqueue(events: [.textDelta(partial)])
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        model.explainFile(file)
        await model.pendingExplain?.value

        let messages = try #require(model.thread?.messages)
        #expect(messages.count == 1)
        let text = try #require(messages.last?.text)
        #expect(!text.contains(partial))
        #expect(!text.hasPrefix("this is correct"))
        #expect(text.contains("incomplete"))
    }

    // MARK: - Errors

    @Test func eachAgentErrorBecomesItsNamedMessageInThePanel() async throws {
        let cases: [AgentError] = [
            .claudeNotFound(searchedPaths: ["/a/claude", "/b/claude"]),
            .notLoggedIn,
            .noNetwork,
            .timedOut(afterSeconds: 60),
            .failed(reason: "exit 1: boom"),
        ]

        for agentError in cases {
            let agent = FakeDiffAgent()
            agent.enqueue(events: [], error: agentError)
            let (model, _) = try await loadModel(agent: agent)
            let file = try #require(model.files.first)

            model.explainFile(file)
            await model.pendingExplain?.value

            let reply = try #require(model.thread?.messages.last)
            #expect(reply.role == .agent)
            #expect(reply.text == agentError.errorDescription)
            #expect(model.isThinking == false)
        }
    }

    // MARK: - Queue

    @Test func aSecondExplainWaitsAndAThirdReplacesTheWaitingOne() async throws {
        let agent = FakeDiffAgent()
        agent.parkCall(at: 0)
        agent.enqueue(events: [.textDelta("from-A"), .finished])
        agent.enqueue(events: [.textDelta("from-C"), .finished])

        let (model, _) = try await loadModel(
            agent: agent,
            files: [
                (path: "Sources/A.swift", body: "@@ -1 +1 @@\n-a0\n+a1\n"),
                (path: "Sources/B.swift", body: "@@ -1 +1 @@\n-b0\n+b1\n"),
                (path: "Sources/C.swift", body: "@@ -1 +1 @@\n-c0\n+c1\n"),
            ]
        )
        let fileA = try #require(model.file(atPath: "Sources/A.swift"))
        let fileB = try #require(model.file(atPath: "Sources/B.swift"))
        let fileC = try #require(model.file(atPath: "Sources/C.swift"))

        model.explainFile(fileA)
        let running = model.pendingExplain
        await agent.waitUntilParkStarts()
        #expect(agent.requestCount == 1)

        model.explainFile(fileB)
        model.explainFile(fileC)
        // Still only the running call — B was replaced by C before A finished.
        #expect(agent.requestCount == 1)

        agent.releasePark()
        await running?.value
        await model.pendingExplain?.value

        #expect(agent.requestCount == 2)
        #expect(agent.request(at: 0)?.filePath == "Sources/A.swift")
        #expect(agent.request(at: 1)?.filePath == "Sources/C.swift")
        #expect(model.thread?.messages.last?.text == "from-C")
    }

    // MARK: - Cache

    @Test func aCompletedExplanationIsReusedWithoutCallingTheAgentAgain() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("cached answer"), .finished])
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        model.explainFile(file)
        await model.pendingExplain?.value
        #expect(agent.requestCount == 1)

        model.closeChat()
        model.explainFile(file)

        #expect(agent.requestCount == 1)
        #expect(model.pendingExplain == nil)
        #expect(model.isChatOpen)
        #expect(model.thread?.messages.last?.text == "cached answer")
    }

    // MARK: - Mapping

    @Test func chatModelAndReasoningEffortMapIntoTheAgentRequest() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("ok"), .finished])
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        model.chatModel = .haiku
        model.reasoningEffort = .low
        model.explainFile(file)
        await model.pendingExplain?.value

        let request = try #require(agent.request(at: 0))
        #expect(request.model == .haiku)
        #expect(request.effort == .low)

        agent.enqueue(events: [.textDelta("ok2"), .finished])
        // Force a different file path so cache does not short-circuit.
        let runner = FakeCommandRunner()
        let session = session(compareName: "feature-2")
        await stubSuccessfulPatch(
            on: runner,
            session: session,
            files: [(path: "Sources/Other.swift", body: "@@ -1 +1 @@\n-x\n+y\n")]
        )
        let model2 = DiffModel(git: GitService(runner: runner), agent: agent)
        model2.chatModel = .fable
        model2.reasoningEffort = .max
        model2.load(session)
        await model2.pendingLoad?.value
        let other = try #require(model2.files.first)
        model2.explainFile(other)
        await model2.pendingExplain?.value

        let request2 = try #require(agent.request(at: 1))
        #expect(request2.model == .fable)
        #expect(request2.effort == .max)
        #expect(DiffChatModelOption.opus5.agentModel == .opus)
        #expect(DiffChatModelOption.sonnet.agentModel == .sonnet)
        #expect(DiffReasoningEffort.medium.agentEffort == .medium)
        #expect(DiffReasoningEffort.high.agentEffort == .high)
    }

    @Test func theAgentRequestCarriesThatFilesPatchNotAnotherFiles() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("about B"), .finished])
        let bodyA = "@@ -1 +1 @@\n-a-old\n+a-new\n"
        let bodyB = "@@ -2 +2 @@\n-b-old\n+b-new\n"
        let (model, session) = try await loadModel(
            agent: agent,
            files: [
                (path: "Sources/A.swift", body: bodyA),
                (path: "Sources/B.swift", body: bodyB),
            ]
        )
        let fileB = try #require(model.file(atPath: "Sources/B.swift"))

        model.explainFile(fileB)
        await model.pendingExplain?.value

        let request = try #require(agent.request(at: 0))
        #expect(request.filePath == "Sources/B.swift")
        #expect(request.patch.contains("-b-old"))
        #expect(request.patch.contains("+b-new"))
        #expect(!request.patch.contains("-a-old"))
        #expect(!request.patch.contains("+a-new"))
        #expect(request.repositoryRoot == session.repository.rootURL)
        #expect(request.baseName == "main")
        #expect(request.compareName == "feature")
    }

    @Test func binaryAndNoContentFilesCannotBeExplained() async throws {
        let agent = FakeDiffAgent()
        let runner = FakeCommandRunner()
        let session = session()
        await stubBinaryAndTextPatch(on: runner, session: session)
        let model = DiffModel(git: GitService(runner: runner), agent: agent)
        model.load(session)
        await model.pendingLoad?.value

        let text = try #require(model.file(atPath: "Sources/Text.swift"))
        let binary = try #require(model.file(atPath: "Assets/icon.png"))
        #expect(model.canExplainFile(text))
        #expect(model.canExplainFile(binary) == false)

        model.explainFile(binary)
        #expect(agent.requestCount == 0)
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)
    }

    // MARK: - Tool activity

    @Test func toolStartedKeepsActivityVisibleAfterTextHasAlreadyArrived() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [
            .textDelta("I'll check."),
            .toolStarted(command: "git show HEAD:Sources/A.swift"),
            .textDelta(" The change is a rename."),
            .finished,
        ])
        agent.pauseAfterYielding(2)
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        model.explainFile(file)
        await agent.waitUntilMidStreamPark()
        let sawActivity = await waitUntil {
            model.isThinking && model.thinkingActivityLabel == "Running git show"
        }
        #expect(sawActivity)
        #expect(model.thread?.messages.last?.text == "I'll check.")

        agent.releaseMidStreamPark()
        await model.pendingExplain?.value

        #expect(model.isThinking == false)
        #expect(model.thinkingActivityLabel == nil)
        #expect(model.thread?.messages.last?.text == "I'll check. The change is a rename.")
    }

    @Test func toolStartedShowsActivityWhenNoTextHasArrivedYet() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [
            .toolStarted(command: "git status"),
            .textDelta("Working tree is clean around this change."),
            .finished,
        ])
        agent.pauseAfterYielding(1)
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        model.explainFile(file)
        await agent.waitUntilMidStreamPark()
        let sawActivity = await waitUntil {
            model.isThinking && model.thinkingActivityLabel == "Running git status"
        }
        #expect(sawActivity)
        #expect(model.thread?.messages.isEmpty == true)

        agent.releaseMidStreamPark()
        await model.pendingExplain?.value
        #expect(model.isThinking == false)
        #expect(model.thinkingActivityLabel == nil)
    }

    @Test func readableToolActivityPrefersTheGitVerbOverAShellDump() {
        #expect(
            DiffModel.readableToolActivity("git diff main...feature") == "Running git diff"
        )
        #expect(
            DiffModel.readableToolActivity("git show HEAD:path/to/File.swift")
                == "Running git show"
        )
        #expect(DiffModel.readableToolActivity("git status") == "Running git status")
        #expect(DiffModel.readableToolActivity("") == "Working")
    }

    // MARK: - Thread history

    @Test func explainingASecondFileAppendsWithoutErasingTheFirst() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("about A"), .finished])
        agent.enqueue(events: [.textDelta("about B"), .finished])
        let (model, _) = try await loadModel(
            agent: agent,
            files: [
                (path: "Sources/A.swift", body: "@@ -1 +1 @@\n-a0\n+a1\n"),
                (path: "Sources/B.swift", body: "@@ -1 +1 @@\n-b0\n+b1\n"),
            ]
        )
        let fileA = try #require(model.file(atPath: "Sources/A.swift"))
        let fileB = try #require(model.file(atPath: "Sources/B.swift"))

        model.explainFile(fileA)
        await model.pendingExplain?.value
        model.explainFile(fileB)
        await model.pendingExplain?.value

        let messages = try #require(model.thread?.messages)
        #expect(messages.count == 2)
        #expect(messages[0].text == "about A")
        #expect(messages[0].location == "A.swift")
        #expect(messages[1].text == "about B")
        #expect(messages[1].location == "B.swift")
    }

    @Test func clickingAnAlreadyExplainedFileDoesNotCallTheAgentAndScrollsToIt() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("about A"), .finished])
        agent.enqueue(events: [.textDelta("about B"), .finished])
        let (model, _) = try await loadModel(
            agent: agent,
            files: [
                (path: "Sources/A.swift", body: "@@ -1 +1 @@\n-a0\n+a1\n"),
                (path: "Sources/B.swift", body: "@@ -1 +1 @@\n-b0\n+b1\n"),
            ]
        )
        let fileA = try #require(model.file(atPath: "Sources/A.swift"))
        let fileB = try #require(model.file(atPath: "Sources/B.swift"))

        model.explainFile(fileA)
        await model.pendingExplain?.value
        let firstMessageID = try #require(model.thread?.messages.first?.id)

        model.explainFile(fileB)
        await model.pendingExplain?.value
        #expect(agent.requestCount == 2)
        #expect(model.thread?.messages.count == 2)

        model.closeChat()
        model.clearChatScrollRequest()
        model.explainFile(fileA)

        #expect(agent.requestCount == 2)
        #expect(model.pendingExplain == nil)
        #expect(model.isChatOpen)
        #expect(model.thread?.messages.count == 2)
        #expect(model.thread?.messages.map(\.text) == ["about A", "about B"])
        let scroll = try #require(model.chatScrollRequest)
        #expect(scroll.messageID == firstMessageID)
    }

    @Test func theSameFileNeverAppearsTwiceInTheThread() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("first try incomplete")])
        agent.enqueue(events: [.textDelta("second try complete"), .finished])
        let (model, _) = try await loadModel(agent: agent)
        let file = try #require(model.files.first)

        model.explainFile(file)
        await model.pendingExplain?.value
        #expect(model.thread?.messages.count == 1)

        model.explainFile(file)
        await model.pendingExplain?.value

        let messages = try #require(model.thread?.messages)
        #expect(messages.count == 1)
        #expect(messages[0].text == "second try complete")
        #expect(messages[0].location == "A.swift")
        #expect(agent.requestCount == 2)
    }

    /// Lets the MainActor consumer finish handling a yielded event before we assert.
    private func waitUntil(
        attempts: Int = 100,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}
