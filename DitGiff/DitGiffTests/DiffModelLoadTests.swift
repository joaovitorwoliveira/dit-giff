import Foundation
import Testing

@testable import DitGiff

/// Load path for a live `DiffModel`: FakeCommandRunner canned git, failure copy, and
/// cancel-on-return-to-Welcome. Sample-data construction is covered in DiffModelTests.
@MainActor
struct DiffModelLoadTests {

    // MARK: - Harness

    /// Parks git calls whose arguments contain `marker` until `releasePark` runs.
    private final class ParkingCommandRunner: CommandRunner, @unchecked Sendable {
        private let inner = FakeCommandRunner()
        private let lock = NSLock()
        private var parkMarker: String?
        private var parkContinuation: CheckedContinuation<Void, Never>?
        private var startedContinuation: CheckedContinuation<Void, Never>?

        func stub(
            _ executable: String,
            _ arguments: [String] = [],
            standardOutput: String = "",
            standardError: String = "",
            exitCode: Int32 = 0
        ) async {
            await inner.stub(
                executable,
                arguments,
                standardOutput: standardOutput,
                standardError: standardError,
                exitCode: exitCode
            )
        }

        func parkCommandsMatching(_ marker: String) {
            lock.lock()
            parkMarker = marker
            lock.unlock()
        }

        func waitUntilParkStarts() async {
            lock.lock()
            if parkContinuation != nil {
                lock.unlock()
                return
            }
            lock.unlock()
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

        func run(_ request: CommandRequest) async throws -> CommandOutput {
            lock.lock()
            let marker = parkMarker
            let shouldPark = request.executable == "git"
                && marker.map { needle in request.arguments.contains { $0.contains(needle) } } == true
            lock.unlock()

            if shouldPark {
                lock.lock()
                let started = startedContinuation
                startedContinuation = nil
                lock.unlock()
                started?.resume()

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    parkContinuation = continuation
                    lock.unlock()
                }
                try Task.checkCancellation()
            }

            return try await inner.run(request)
        }

        /// Same park gate as `run`: while parked, no events and no finish; after
        /// release, forwards to the inner stub stream.
        func stream(
            _ request: CommandRequest
        ) -> AsyncThrowingStream<CommandStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        self.lock.lock()
                        let marker = self.parkMarker
                        let shouldPark = request.executable == "git"
                            && marker.map { needle in request.arguments.contains { $0.contains(needle) } } == true
                        self.lock.unlock()

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
                            try Task.checkCancellation()
                        }

                        for try await event in self.inner.stream(request) {
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
    }

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
        path: String = "Sources/Billing/BillingGuard.swift"
    ) async {
        let range = "\(session.base.fullRef)...\(session.compare.fullRef)"
        let unified = """
        diff --git a/\(path) b/\(path)
        index d95f3ad..5ea2ed4 100644
        --- a/\(path)
        +++ b/\(path)
        @@ -1 +1 @@
        -old
        +new
        """
        let raw = ":100644 100644 d95f3ad 5ea2ed4 M\0\(path)\0"

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

    private func stubSuccessfulPatch(
        on runner: ParkingCommandRunner,
        session: DiffSession,
        path: String = "Sources/Billing/BillingGuard.swift"
    ) async {
        let range = "\(session.base.fullRef)...\(session.compare.fullRef)"
        let unified = """
        diff --git a/\(path) b/\(path)
        index d95f3ad..5ea2ed4 100644
        --- a/\(path)
        +++ b/\(path)
        @@ -1 +1 @@
        -old
        +new
        """
        let raw = ":100644 100644 d95f3ad 5ea2ed4 M\0\(path)\0"

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

    // MARK: - Success

    @Test func loadsAPatchFromADiffSessionIntoDrawableFiles() async throws {
        let runner = FakeCommandRunner()
        let session = session()
        await stubSuccessfulPatch(on: runner, session: session)

        let model = DiffModel(git: GitService(runner: runner))
        #expect(model.loadState == .loading)

        model.load(session)
        await model.pendingLoad?.value

        #expect(model.loadState == .loaded)
        #expect(model.compareBranch == "feature")
        #expect(model.baseBranch == "main")
        #expect(model.repositoryName == "billing-service")
        #expect(model.fileCountText == "1 file")
        #expect(model.additionsText == "+1")
        #expect(model.deletionsText == "\(DiffFormat.minusSign)1")
        #expect(model.files.count == 1)
        #expect(model.sectionFiles.count == 1)
        #expect(model.sectionFiles[0].path == "Sources/Billing/BillingGuard.swift")
        #expect(model.sectionFiles[0].hunks.count == 1)
        #expect(model.sectionFiles[0].hunks[0].explanation == nil)
        #expect(model.canExplain(model.sectionFiles[0].hunks[0]) == false)
        #expect(model.totalHunkCount == 1)
        #expect(model.progressText == "0 of 1 hunks read")
    }

    // MARK: - Failure

    @Test func surfacesAGitFailureWithTheNamedMessage() async throws {
        let runner = FakeCommandRunner()
        let session = session()
        let range = "\(session.base.fullRef)...\(session.compare.fullRef)"

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
            standardError: "fatal: base...compare: no merge base\n",
            exitCode: 128
        )

        let model = DiffModel(git: GitService(runner: runner))
        model.load(session)
        await model.pendingLoad?.value

        let expected = GitError.noCommonAncestor(base: "main", compare: "feature")
        #expect(model.loadState == .failed(message: expected.errorDescription ?? ""))
        #expect(model.files.isEmpty)
        #expect(model.sectionFiles.isEmpty)
    }

    // MARK: - Cancel

    @Test func returningToWelcomeCancelsAnInFlightLoad() async throws {
        let runner = ParkingCommandRunner()
        let session = session()
        await stubSuccessfulPatch(on: runner, session: session)
        runner.parkCommandsMatching("diff")

        let model = DiffModel(git: GitService(runner: runner))
        let app = AppModel(
            welcomeModel: AppModel().welcomeModel,
            diffModel: model
        )

        app.openDiff(session)
        #expect(model.loadState == .loading)

        await runner.waitUntilParkStarts()
        app.returnToWelcome()
        runner.releasePark()

        // Give a cancelled task a beat to finish without writing.
        try await Task.sleep(for: .milliseconds(50))

        #expect(app.route == .welcome)
        #expect(app.activeDiffSession == nil)
        #expect(model.files.isEmpty)
        #expect(model.sectionFiles.isEmpty)
        #expect(model.loadState == .loading)
        #expect(model.compareBranch.isEmpty)
        #expect(model.repositoryName.isEmpty)
    }

    // MARK: - Session race

    @Test func aNewerSessionLoadWinsOverAStaleInFlightLoad() async throws {
        let runner = ParkingCommandRunner()
        let first = session(compareName: "feature-old")
        let second = session(compareName: "feature-new")
        await stubSuccessfulPatch(
            on: runner,
            session: first,
            path: "Sources/Old.swift"
        )
        await stubSuccessfulPatch(
            on: runner,
            session: second,
            path: "Sources/New.swift"
        )

        // Park only the first session's diff — the second must finish without waiting.
        runner.parkCommandsMatching("refs/heads/feature-old")

        let model = DiffModel(git: GitService(runner: runner))
        model.load(first)
        await runner.waitUntilParkStarts()
        #expect(model.loadState == .loading)

        model.load(second)
        await model.pendingLoad?.value

        #expect(model.loadState == .loaded)
        #expect(model.compareBranch == "feature-new")
        #expect(model.files.map(\.path) == ["Sources/New.swift"])
        #expect(model.sectionFiles.map(\.path) == ["Sources/New.swift"])

        // Late finish of the first load must not overwrite the newer session.
        runner.releasePark()
        try await Task.sleep(for: .milliseconds(80))

        #expect(model.compareBranch == "feature-new")
        #expect(model.files.map(\.path) == ["Sources/New.swift"])
        #expect(model.sectionFiles.map(\.path) == ["Sources/New.swift"])
    }

    // MARK: - Live session never invents agent copy

    /// Regression net: a live session without an injected agent stays silent on every
    /// entry that used to spew DiffSampleData. With an agent, only that agent's text
    /// appears — never canned sample copy.
    @Test func aLiveSessionNeverProducesCannedAgentMessagesThroughAnyEntryPoint() async throws {
        let runner = FakeCommandRunner()
        let session = session()
        await stubSuccessfulPatch(on: runner, session: session)

        let model = DiffModel(git: GitService(runner: runner))
        model.load(session)
        await model.pendingLoad?.value

        #expect(model.loadState == .loaded)
        #expect(model.canUseSampleAgent == false)
        #expect(model.canOpenChat == false)
        #expect(model.canPresentSelectionPopover == false)
        #expect(model.thinkingIndicator == nil)

        let hunk = try #require(model.sectionFiles.first?.hunks.first)
        let file = try #require(model.sectionFiles.first)
        #expect(model.canExplain(hunk) == false)
        #expect(model.canExplainFile(file) == false)

        // 1. Explain selection
        model.selectLines(inHunkWithID: hunk.id, from: 0, through: 0)
        #expect(model.canExplainSelection == false)
        #expect(model.canAskAboutSelection == false)
        model.explainSelection()
        await model.pendingReply?.value
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)
        #expect(model.isThinking == false)
        #expect(model.pendingReply == nil)

        // 2. Ask about selection (non-empty) and empty → explainSelection
        model.selectLines(inHunkWithID: hunk.id, from: 0, through: 0)
        model.askAboutSelection("Does this crash?")
        await model.pendingReply?.value
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)

        model.selectLines(inHunkWithID: hunk.id, from: 0, through: 0)
        model.askAboutSelection("   ")
        await model.pendingReply?.value
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)

        // 3. Composer send
        model.send("What changed here?")
        await model.pendingReply?.value
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)
        #expect(model.isThinking == false)

        // 4. General chat open (opening agent message)
        model.openChat()
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)

        // 5. Hunk / file explain with no agent — still silent, no sample copy
        model.explain(hunk)
        model.explainFile(file)
        await model.pendingReply?.value
        await model.pendingExplain?.value
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)
        #expect(model.isThinking == false)

        // Selection highlight may remain; the popover must stay unavailable.
        model.selectLines(inHunkWithID: hunk.id, from: 0, through: 0)
        #expect(model.selection != nil)
        #expect(model.canPresentSelectionPopover == false)

        // With a real agent, the panel shows only what the agent streamed — never
        // DiffSampleData's canned strings.
        let agent = LiveGuardianAgent(
            events: [.textDelta("only from the agent"), .finished]
        )
        let live = DiffModel(git: GitService(runner: runner), agent: agent)
        // Re-stub: FakeCommandRunner consumes stubs once.
        await stubSuccessfulPatch(on: runner, session: session)
        live.load(session)
        await live.pendingLoad?.value
        let liveFile = try #require(live.sectionFiles.first)
        #expect(live.canExplainFile(liveFile))
        #expect(live.canUseSampleAgent == false)
        #expect(live.canOpenChat == false)
        #expect(live.canPresentSelectionPopover == false)

        live.explainFile(liveFile)
        await live.pendingExplain?.value
        let text = try #require(live.thread?.messages.last?.text)
        #expect(text == "only from the agent")
        #expect(text != DiffSampleData.openingAgentMessage)
        #expect(text != DiffSampleData.fallbackReply)
        #expect(!text.contains("force-unwrap"))
    }
}

/// Minimal agent for the guardian's positive path — not shared with other suites.
private final class LiveGuardianAgent: DiffAgent, @unchecked Sendable {
    private let events: [AgentEvent]

    init(events: [AgentEvent]) {
        self.events = events
    }

    func explainFile(
        _ request: AgentExplainRequest
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

