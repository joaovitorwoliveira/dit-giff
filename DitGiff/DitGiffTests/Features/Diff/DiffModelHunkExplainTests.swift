import Foundation
import Testing

@testable import DitGiff

/// Live `DiffModel` hunk explain: patch slice, streaming, queue, cache, sample guard.
@MainActor
struct DiffModelHunkExplainTests {

    // MARK: - Fake agent

    private final class FakeDiffAgent: DiffAgent, @unchecked Sendable {
        private let lock = NSLock()
        private var scripted: [[AgentEvent]] = []
        private var scriptedErrors: [AgentError?] = []
        private var scriptIndex = 0
        private(set) var requests: [AgentExplainRequest] = []

        private var parkCallIndex: Int?
        private var parkContinuation: CheckedContinuation<Void, Never>?
        private var startedContinuation: CheckedContinuation<Void, Never>?

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

        func releasePark() {
            lock.lock()
            let continuation = parkContinuation
            parkContinuation = nil
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

                    for event in events {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        continuation.yield(event)
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

    private func session() -> DiffSession {
        DiffSession(
            repository: GitRepository(
                rootURL: URL(fileURLWithPath: "/repo/billing-service", isDirectory: true),
                displayName: "billing-service",
                head: .branch("feature")
            ),
            base: GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil),
            compare: GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil),
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

    private func loadModel(
        agent: FakeDiffAgent,
        files: [(path: String, body: String)] = [
            (path: "Sources/A.swift", body: "@@ -1 +1 @@\n-old\n+new\n")
        ]
    ) async throws -> DiffModel {
        let runner = FakeCommandRunner()
        let session = session()
        await stubSuccessfulPatch(on: runner, session: session, files: files)
        let model = DiffModel(git: GitService(runner: runner), agent: agent)
        model.load(session)
        await model.pendingLoad?.value
        #expect(model.loadState == .loaded)
        return model
    }

    // MARK: - Patch slice

    @Test func explainHunkSendsThatHunksPatchNotTheWholeFile() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("about second hunk"), .finished])
        let body = """
            @@ -1 +1 @@
            -first-old
            +first-new
            @@ -20 +20 @@
            -second-old
            +second-new
            """
        let model = try await loadModel(
            agent: agent,
            files: [(path: "Sources/A.swift", body: body)]
        )
        let file = try #require(model.files.first)
        let secondHunk = try #require(file.hunks.dropFirst().first)
        let fullPatch = try #require(model.filePatchBodies[file.path])

        #expect(model.canExplain(secondHunk))
        model.explain(secondHunk)
        await model.pendingExplain?.value

        let request = try #require(agent.request(at: 0))
        #expect(request.filePath == "Sources/A.swift")
        #expect(request.patch.contains("second-old"))
        #expect(request.patch.contains("second-new"))
        #expect(!request.patch.contains("first-old"))
        #expect(!request.patch.contains("first-new"))
        #expect(request.patch != fullPatch)
        if case let .hunk(id, location) = request.scope {
            #expect(id == secondHunk.id)
            #expect(location == secondHunk.location)
        } else {
            Issue.record("Expected hunk scope")
        }
    }

    // MARK: - canExplain

    @Test func canExplainReflectsAgentAndPatchNotCannedCopy() async throws {
        let agent = FakeDiffAgent()
        let model = try await loadModel(agent: agent)
        let hunk = try #require(model.sectionFiles.first?.hunks.first)

        #expect(hunk.explanation == nil)
        #expect(model.canExplain(hunk))

        let bare = DiffHunk(
            id: "missing#0",
            filePath: "Sources/Missing.swift",
            header: "@@ -1 +1 @@",
            location: "Missing.swift:1",
            note: nil,
            explanation: nil,
            reply: nil,
            lines: []
        )
        #expect(model.canExplain(bare) == false)
    }

    @Test func sampleHunkWithoutExplanationStaysDisabled() {
        let model = DiffModel()
        let bare = DiffHunk(
            id: "bare",
            filePath: "Sources/Bare.swift",
            header: "@@ -1 +1 @@",
            location: "Bare.swift:1",
            note: nil,
            explanation: nil,
            reply: nil,
            lines: [
                DiffLine(
                    oldNumber: 1,
                    newNumber: 1,
                    kind: .context,
                    segments: [DiffLineSegment(text: "x")]
                )
            ]
        )

        #expect(model.canExplain(bare) == false)
        model.explain(bare)
        #expect(model.isChatOpen == false)
        #expect(model.thread == nil)
    }

    @Test func sampleHunkWithExplanationStillUsesCannedCopy() async throws {
        let model = DiffModel()
        let hunk = try #require(model.sectionHunks.first { $0.explanation != nil })

        #expect(model.canExplain(hunk))
        model.explain(hunk)
        #expect(model.isChatOpen)
        #expect(model.isThinking)

        await model.pendingReply?.value
        let reply = try #require(model.thread?.messages.last)
        #expect(reply.text == hunk.explanation)
        #expect(reply.hunkID == hunk.id)
    }

    // MARK: - Stream without finished

    @Test func hunkStreamWithoutFinishedIsFailureNotPartialProse() async throws {
        let agent = FakeDiffAgent()
        agent.enqueue(events: [.textDelta("partial hunk answer")])
        let model = try await loadModel(agent: agent)
        let hunk = try #require(model.sectionFiles.first?.hunks.first)

        model.explain(hunk)
        await model.pendingExplain?.value

        let text = try #require(model.thread?.messages.last?.text)
        #expect(!text.contains("partial hunk answer"))
        #expect(text.contains("incomplete"))
    }

    // MARK: - Queue

    @Test func fileAndHunkShareOneDeepQueueAndReplaceTheWaiter() async throws {
        let agent = FakeDiffAgent()
        agent.parkCall(at: 0)
        agent.enqueue(events: [.textDelta("from-file"), .finished])
        agent.enqueue(events: [.textDelta("from-hunk"), .finished])

        let body = """
            @@ -1 +1 @@
            -a0
            +a1
            @@ -2 +2 @@
            -b0
            +b1
            """
        let model = try await loadModel(
            agent: agent,
            files: [(path: "Sources/A.swift", body: body)]
        )
        let file = try #require(model.files.first)
        let firstHunk = try #require(file.hunks.first)
        let secondHunk = try #require(file.hunks.dropFirst().first)

        model.explainFile(file)
        let running = model.pendingExplain
        await agent.waitUntilParkStarts()
        #expect(agent.requestCount == 1)

        model.explain(firstHunk)
        model.explain(secondHunk)
        #expect(agent.requestCount == 1)

        agent.releasePark()
        await running?.value
        await model.pendingExplain?.value

        #expect(agent.requestCount == 2)
        if case .hunk = agent.request(at: 1)?.scope {
            // expected
        } else {
            Issue.record("Second call should be a hunk explain")
        }
        #expect(model.thread?.messages.last?.text == "from-hunk")
    }
}
