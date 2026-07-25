import Foundation
import Observation

/// The pause before a canned answer arrives. It is a seam so tests do not wait on the
/// clock, and so the delay stays out of the rules it decorates.
nonisolated protocol DiffReplyDelay: Sendable {
    func wait() async throws
}

/// What the prototype does: a wait long enough to read the question back.
nonisolated struct RandomDiffReplyDelay: DiffReplyDelay {
    let milliseconds: ClosedRange<Int>

    init(milliseconds: ClosedRange<Int>) {
        self.milliseconds = milliseconds
    }

    func wait() async throws {
        try await Task.sleep(for: .milliseconds(Int.random(in: milliseconds)))
    }
}

/// Live sessions have no fake round-trip. Slice 4 will own real latency.
nonisolated struct NullDiffReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}

/// The only door from `DiffModel` into `DiffSampleData`'s canned agent copy.
/// Present in sample/preview mode; **absent** in a live session. Every path that would
/// invent an agent answer must go through this value — so a live model cannot reach
/// that copy without growing a second source, which is the point of Slice 4.
private struct DiffCannedAgent: Sendable {
    let openingMessage: String
    let thinkingIndicator: DiffThinkingIndicator
    let fallbackReply: String
    let defaultChatModel: DiffChatModelOption
    let defaultReasoningEffort: DiffReasoningEffort

    func explainSelectionReply(lineCountLabel: String) -> String {
        DiffSampleData.explainSelectionReply(lineCountLabel: lineCountLabel)
    }

    func selectionQuestionReply(location: String, question: String) -> String {
        DiffSampleData.selectionQuestionReply(location: location, question: question)
    }

    static var prototype: DiffCannedAgent {
        DiffCannedAgent(
            openingMessage: DiffSampleData.openingAgentMessage,
            thinkingIndicator: DiffSampleData.thinkingIndicator,
            fallbackReply: DiffSampleData.fallbackReply,
            defaultChatModel: DiffSampleData.defaultChatModel,
            defaultReasoningEffort: DiffSampleData.defaultReasoningEffort
        )
    }
}

/// State of the diff screen. Every rule — what viewed implies, what counts as read,
/// what a selection is called, what the agent answers — lives here, so the views stay a
/// rendering of this object and nothing else.
@MainActor
@Observable
final class DiffModel {
    private(set) var files: [DiffFile]
    /// The files the center viewer shows, in its own order.
    private(set) var sectionFiles: [DiffFile]

    /// Sample data for previews and unit tests, or a live session driven by git.
    private let usesSampleData: Bool
    private let git: GitService?
    /// Sample/preview only. A live session never holds one — that is what keeps
    /// DiffSampleData copy unreachable from real diffs.
    private let cannedAgent: DiffCannedAgent?
    /// Live AI seam. Nil in sample mode and in live sessions that have no agent yet.
    private let agent: (any DiffAgent)?

    // MARK: - Load

    private(set) var loadState: DiffLoadState
    /// The in-flight patch load. Tests await or cancel it instead of racing the clock.
    private(set) var pendingLoad: Task<Void, Never>?
    /// Bumped on every load start and on return-to-Welcome so a stale task cannot write.
    private var loadGeneration = 0
    /// Per-file unified body from the last loaded `Patch`. Keyed by destination path.
    private var filePatchBodies: [String: String] = [:]
    private var repositoryRoot: URL?

    // MARK: - Sidebar

    var filter = "" {
        didSet {
            guard filter != oldValue else { return }
            refreshFilterCaches()
        }
    }
    private(set) var isSidebarOpen = true
    /// Cached from `files` + `filter`. Invalidated only when either changes.
    private(set) var filteredFiles: [DiffFile] = []
    /// Cached tree of `filteredFiles`. Invalidated with the filter caches.
    private(set) var fileTree: [DiffTreeNode] = []
    /// Test seam: how often the filter / tree caches were rebuilt.
    private(set) var filterCacheRefreshCount = 0

    // MARK: - Reading state

    private(set) var viewedPaths: Set<String>
    private(set) var collapsedPaths: Set<String>
    private(set) var readHunkIDs: Set<String> = []
    /// Cached progress. Invalidated when viewed / read / section files / baseline change.
    private(set) var readHunkCount: Int = 0
    /// Test seam: how often progress was recomputed.
    private(set) var readProgressRefreshCount = 0
    /// Directory path → viewed aggregate over all descendants. Rebuilt with viewed / tree.
    private(set) var directoryViewedStates: [String: DiffAggregateState] = [:]
    /// Test seam: how often directory viewed aggregates were recomputed.
    private(set) var directoryViewedStateRefreshCount = 0

    // MARK: - Selection

    private(set) var selection: DiffSelection?

    // MARK: - Sidebar → reader navigation

    /// The file last chosen in the change map. Highlight only — not the same as viewed.
    private(set) var focusedFilePath: String?
    /// Consumed by the viewer to animate a scroll. `nil` when idle.
    private(set) var readerScrollRequest: DiffReaderScrollRequest?
    private var readerScrollNonce: UInt = 0

    // MARK: - Chat

    private(set) var isChatOpen = false
    private(set) var thread: DiffChatThread?
    private(set) var isThinking = false
    /// Overrides the cycling thinking words while a tool is running — keeps the panel
    /// alive when the agent is silent between text deltas.
    private(set) var thinkingActivityLabel: String?
    /// Consumed by the chat panel to scroll to an existing explanation.
    private(set) var chatScrollRequest: DiffChatScrollRequest?
    private var chatScrollNonce: UInt = 0
    var chatModel: DiffChatModelOption
    var reasoningEffort: DiffReasoningEffort
    /// The fake round trip currently in flight. Tests await it instead of sleeping.
    private(set) var pendingReply: Task<Void, Never>?
    /// The live explain currently in flight (running slot of the one-deep queue).
    private(set) var pendingExplain: Task<Void, Never>?

    private let replyDelay: DiffReplyDelay
    /// Hunks already read before this sample, so the progress starts where the diff does.
    /// Zero for a live session — only the hunks on screen count.
    private var readHunkBaseline: Int
    private var closedDirectories: Set<String> = []
    private var usedHunkReplies: Set<String> = []
    private var nextMessageID = 0
    /// Completed file explanations only — a stream without `.finished` never lands here.
    private var completedFileExplanations: [String: String] = [:]
    /// One thread entry per file path — used to scroll back and to enforce uniqueness.
    private var explanationMessageIDs: [String: Int] = [:]
    private var inFlightExplainPath: String?
    /// At most one waiter. A newer request replaces whoever was waiting.
    private var queuedExplainPath: String?
    private var streamingMessageID: Int?
    private var streamingFilePath: String?
    /// Bumped when explains are cancelled so a stale task cannot start the queue.
    private var explainGeneration = 0

    // MARK: - Headline (session / sample)

    private(set) var compareBranch: String
    private(set) var baseBranch: String
    private(set) var repositoryName: String
    private var declaredFileCount: Int
    private var declaredAdditions: Int
    private var declaredDeletions: Int
    private var declaredTotalHunkCount: Int

    /// Sample / preview / unit-test construction — no git, DiffSampleData on screen,
    /// and a `DiffCannedAgent` so the prototype chat still answers.
    init(
        replyDelay: DiffReplyDelay = RandomDiffReplyDelay(
            milliseconds: DiffSampleData.replyDelayRange
        ),
        readHunkBaseline: Int = DiffSampleData.readHunkBaseline
    ) {
        let agent = DiffCannedAgent.prototype
        self.replyDelay = replyDelay
        self.readHunkBaseline = readHunkBaseline
        self.git = nil
        self.usesSampleData = true
        self.cannedAgent = agent
        self.agent = nil
        self.loadState = .loaded
        self.chatModel = agent.defaultChatModel
        self.reasoningEffort = agent.defaultReasoningEffort
        files = DiffSampleData.files
        sectionFiles = DiffSampleData.sectionFiles
        viewedPaths = DiffSampleData.defaultViewedPaths
        collapsedPaths = DiffSampleData.defaultViewedPaths
        compareBranch = DiffSampleData.compareBranch
        baseBranch = DiffSampleData.baseBranch
        repositoryName = ""
        declaredFileCount = DiffSampleData.declaredFileCount
        declaredAdditions = DiffSampleData.declaredAdditions
        declaredDeletions = DiffSampleData.declaredDeletions
        declaredTotalHunkCount = DiffSampleData.totalHunkCount
        refreshFilterCaches()
        refreshReadProgress()
    }

    /// Live construction — empty until `load(_:)` runs. Sample canned copy stays absent;
    /// explanations come only from the injected `DiffAgent` when one is present.
    init(
        git: GitService,
        agent: (any DiffAgent)? = nil,
        replyDelay: DiffReplyDelay = NullDiffReplyDelay()
    ) {
        self.replyDelay = replyDelay
        self.readHunkBaseline = 0
        self.git = git
        self.usesSampleData = false
        self.cannedAgent = nil
        self.agent = agent
        self.loadState = .loading
        // Picker defaults only — not agent copy, and not read from DiffSampleData.
        self.chatModel = .opus5
        self.reasoningEffort = .high
        files = []
        sectionFiles = []
        viewedPaths = []
        collapsedPaths = []
        compareBranch = ""
        baseBranch = ""
        repositoryName = ""
        declaredFileCount = 0
        declaredAdditions = 0
        declaredDeletions = 0
        declaredTotalHunkCount = 0
        refreshFilterCaches()
        refreshReadProgress()
    }

    // MARK: - Agent availability

    /// Sample/preview chat, composer, and selection popover. False in a live session
    /// even when a real `DiffAgent` is injected — free-form chat stays Slice 8.
    var canUseSampleAgent: Bool { cannedAgent != nil }

    /// The thinking chrome. Present whenever any answer source can produce a reply.
    var thinkingIndicator: DiffThinkingIndicator? {
        if let cannedAgent {
            return cannedAgent.thinkingIndicator
        }
        if agent != nil {
            return Self.liveThinkingIndicator
        }
        return nil
    }

    /// Selection popover actions all need the sample canned agent. Live keeps them off
    /// until Slice 8.
    var canPresentSelectionPopover: Bool { cannedAgent != nil }

    /// General chat (open + composer) needs the sample canned agent. Live keeps them off.
    var canOpenChat: Bool { cannedAgent != nil }

    /// Glyphs/words for live explain — not DiffSampleData, so a guardian can prove
    /// sample copy never leaks into a real session's agent path.
    private static let liveThinkingIndicator = DiffThinkingIndicator(
        glyphs: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
        words: [
            "Thinking",
            "Reading the file",
            "Tracing call sites",
            "Weighing the trade-off",
        ]
    )

    // MARK: - Headline

    // These describe the whole diff. Sample mode keeps the prototype's declared totals;
    // a live session uses the patch that was just loaded.
    var fileCountText: String {
        declaredFileCount == 1 ? "1 file" : "\(declaredFileCount) files"
    }

    var additionsText: String { "+\(declaredAdditions)" }
    var deletionsText: String { "\(DiffFormat.minusSign)\(declaredDeletions)" }

    // MARK: - Session load

    /// Starts (or restarts) loading the patch for `session`. Sample models ignore this —
    /// they already have something to draw, and tests / previews depend on that.
    func load(_ session: DiffSession) {
        guard !usesSampleData, let git else { return }

        pendingLoad?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        compareBranch = session.compare.displayName
        baseBranch = session.base.displayName
        repositoryName = session.repository.displayName
        repositoryRoot = session.repository.rootURL
        files = []
        sectionFiles = []
        viewedPaths = []
        collapsedPaths = []
        readHunkIDs = []
        selection = nil
        focusedFilePath = nil
        readerScrollRequest = nil
        closedDirectories = []
        filePatchBodies = [:]
        completedFileExplanations = [:]
        explanationMessageIDs = [:]
        chatScrollRequest = nil
        cancelAgentExplain(clearQueue: true)
        // One thread per diff — prose about the previous branch must not survive a switch.
        thread = nil
        isChatOpen = false
        thinkingActivityLabel = nil
        declaredFileCount = 0
        declaredAdditions = 0
        declaredDeletions = 0
        declaredTotalHunkCount = 0
        loadState = .loading
        refreshFilterCaches()
        refreshReadProgress()

        pendingLoad = Task { [git] in
            do {
                let patch = try await git.loadPatch(
                    in: session.repository,
                    base: session.base,
                    compare: session.compare
                )
                guard !Task.isCancelled, generation == loadGeneration else { return }
                apply(patch: patch)
            } catch is CancellationError {
                // Replaced or abandoned — leave state to the newer task / returnToWelcome.
            } catch {
                guard !Task.isCancelled, generation == loadGeneration else { return }
                loadState = .failed(message: Self.presentableMessage(for: error))
            }
        }
    }

    private func apply(patch: Patch) {
        let adapted = PatchAdapter.toDiffFiles(patch)
        files = adapted
        sectionFiles = adapted.filter { !$0.hunks.isEmpty }
        declaredFileCount = adapted.count
        declaredAdditions = adapted.reduce(0) { $0 + $1.additions }
        declaredDeletions = adapted.reduce(0) { $0 + $1.deletions }
        declaredTotalHunkCount = adapted.reduce(0) { $0 + $1.hunks.count }
        var bodies: [String: String] = [:]
        for file in patch.files {
            if let rawBody = file.rawBody {
                bodies[file.path] = rawBody
            }
        }
        filePatchBodies = bodies
        loadState = .loaded
        refreshFilterCaches()
        refreshReadProgress()
    }

    private static func presentableMessage(for error: Error) -> String {
        if let gitError = error as? GitError {
            return gitError.errorDescription ?? String(describing: gitError)
        }
        if let patchError = error as? PatchError {
            return patchError.errorDescription ?? String(describing: patchError)
        }
        return error.localizedDescription
    }

    // MARK: - Sidebar

    func toggleSidebar() {
        isSidebarOpen.toggle()
    }

    private var normalizedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isFiltering: Bool { !normalizedFilter.isEmpty }

    /// Folders start open, and a filter opens all of them: hiding a match behind a
    /// closed folder would be a lie.
    func isDirectoryOpen(_ path: String) -> Bool {
        isFiltering || !closedDirectories.contains(path)
    }

    func toggleDirectory(_ path: String) {
        if closedDirectories.contains(path) {
            closedDirectories.remove(path)
            return
        }
        closedDirectories.insert(path)
    }

    // MARK: - Sidebar → reader navigation

    func isFocusedInSidebar(_ file: DiffFile) -> Bool {
        focusedFilePath == file.path
    }

    /// Sidebar file row click. Marks the file current; scrolls the reader when the file
    /// has hunks. Does not expand a collapsed file — the sticky header is the target.
    func revealFileInReader(_ file: DiffFile) {
        focusedFilePath = file.path
        let sectionPaths = Set(sectionFiles.map(\.path))
        switch DiffFileNavigationResolver.resolve(
            filePath: file.path,
            sectionFilePaths: sectionPaths
        ) {
        case let .scrollToHeader(path):
            readerScrollNonce &+= 1
            readerScrollRequest = DiffReaderScrollRequest(
                path: path,
                nonce: readerScrollNonce,
                attempt: DiffReaderScrollRetry.animatedAttempt
            )
        case .unavailableInReader:
            readerScrollRequest = nil
        }
    }

    /// Advances the reader scroll retry sequence after a corrective delay. When the policy
    /// has no further pass, clears the request so the next sidebar click can fire.
    func advanceReaderScrollRequest() {
        guard let request = readerScrollRequest else { return }
        guard DiffReaderScrollRetry.delayAfter(attempt: request.attempt) != nil else {
            readerScrollRequest = nil
            return
        }
        readerScrollRequest = DiffReaderScrollRequest(
            path: request.path,
            nonce: request.nonce,
            attempt: request.attempt + 1
        )
    }

    /// Ends an in-flight scroll sequence without touching sidebar focus.
    func clearReaderScrollRequest() {
        readerScrollRequest = nil
    }

    // MARK: - Viewed and collapsed

    func isViewed(_ file: DiffFile) -> Bool {
        viewedPaths.contains(file.path)
    }

    func isCollapsed(_ file: DiffFile) -> Bool {
        collapsedPaths.contains(file.path)
    }

    /// Marking a file viewed collapses it — there is nothing left to read. Unmarking
    /// reopens it, which is how the prototype behaves.
    func toggleViewed(_ file: DiffFile) {
        setViewed(!isViewed(file), for: file)
    }

    func toggleCollapsed(_ file: DiffFile) {
        if collapsedPaths.contains(file.path) {
            collapsedPaths.remove(file.path)
            return
        }
        collapsedPaths.insert(file.path)
    }

    private func setViewed(_ isViewed: Bool, for file: DiffFile) {
        var viewed = viewedPaths
        var collapsed = collapsedPaths
        if isViewed {
            viewed.insert(file.path)
            collapsed.insert(file.path)
        } else {
            viewed.remove(file.path)
            collapsed.remove(file.path)
        }
        viewedPaths = viewed
        collapsedPaths = collapsed
        refreshViewedDirectoryStates()
        refreshReadProgress()
    }

    // MARK: - Folder aggregates

    func viewedState(for directory: DiffTreeDirectory) -> DiffAggregateState {
        directoryViewedStates[directory.path] ?? .none
    }

    func collapsedState(for directory: DiffTreeDirectory) -> DiffAggregateState {
        aggregateState(for: directory) { collapsedPaths.contains($0.path) }
    }

    /// Whether a sidebar file row should paint as already read. O(1) set lookup.
    func isDimmedInSidebar(_ file: DiffFile) -> Bool {
        viewedPaths.contains(file.path)
    }

    /// Whether a sidebar folder row should paint as already read. O(1) cache lookup —
    /// only folders whose every descendant is viewed.
    func isDimmedInSidebar(_ directory: DiffTreeDirectory) -> Bool {
        viewedState(for: directory) == .all
    }

    /// Not-all → mark every descendant viewed (and collapsed). All → clear both marks.
    /// Mutates the sets once and refreshes derived caches once — never once per file.
    func toggleViewed(in directory: DiffTreeDirectory) {
        let files = directory.descendantFiles
        guard !files.isEmpty else { return }
        applyViewed(viewedState(for: directory).togglesTowardAll, to: files)
    }

    /// Not-all → collapse every descendant in the reader. All → expand them all.
    /// Does not touch viewed marks or the progress cache.
    func toggleCollapsed(in directory: DiffTreeDirectory) {
        let files = directory.descendantFiles
        guard !files.isEmpty else { return }
        let collapseAll = collapsedState(for: directory).togglesTowardAll
        var next = collapsedPaths
        for file in files {
            if collapseAll {
                next.insert(file.path)
            } else {
                next.remove(file.path)
            }
        }
        collapsedPaths = next
    }

    private func aggregateState(
        for directory: DiffTreeDirectory,
        matching: (DiffFile) -> Bool
    ) -> DiffAggregateState {
        let files = directory.descendantFiles
        let matchingCount = files.reduce(into: 0) { count, file in
            if matching(file) { count += 1 }
        }
        return DiffAggregateState.of(matchingCount: matchingCount, total: files.count)
    }

    private func applyViewed(_ isViewed: Bool, to files: [DiffFile]) {
        var viewed = viewedPaths
        var collapsed = collapsedPaths
        for file in files {
            if isViewed {
                viewed.insert(file.path)
                collapsed.insert(file.path)
            } else {
                viewed.remove(file.path)
                collapsed.remove(file.path)
            }
        }
        viewedPaths = viewed
        collapsedPaths = collapsed
        refreshViewedDirectoryStates()
        refreshReadProgress()
    }

    // MARK: - Read hunks

    /// A viewed file has been read whole, so its hunks count even if none was ticked.
    func isRead(_ hunk: DiffHunk) -> Bool {
        viewedPaths.contains(hunk.filePath) || readHunkIDs.contains(hunk.id)
    }

    /// Unticking a hunk of a file marked viewed contradicts the file: the file stops
    /// being viewed, rather than the tick being ignored. It goes through the same door
    /// as the Viewed button, so the file cannot end up unviewed yet collapsed.
    func toggleRead(_ hunk: DiffHunk) {
        guard isRead(hunk) else {
            readHunkIDs.insert(hunk.id)
            refreshReadProgress()
            return
        }
        readHunkIDs.remove(hunk.id)
        guard let file = file(atPath: hunk.filePath) else {
            refreshReadProgress()
            return
        }
        setViewed(false, for: file)
    }

    private var sectionHunks: [DiffHunk] {
        sectionFiles.flatMap(\.hunks)
    }

    var totalHunkCount: Int { declaredTotalHunkCount }

    var progressText: String {
        "\(readHunkCount) of \(totalHunkCount) hunks read"
    }

    var progressFraction: Double {
        guard totalHunkCount > 0 else { return 0 }
        return min(1, Double(readHunkCount) / Double(totalHunkCount))
    }

    var allRead: Bool {
        readHunkCount >= totalHunkCount
    }

    // MARK: - Selection

    /// The drag gesture works in rows, because that is the granularity it can hit.
    /// Out-of-range rows are clamped rather than dropped: a drag past the last line
    /// still means "to the end".
    func selectLines(inHunkWithID hunkID: String, from: Int, through: Int) {
        guard let hunk = hunk(withID: hunkID), !hunk.lines.isEmpty else {
            selection = nil
            return
        }
        let bounds = 0...(hunk.lines.count - 1)
        let lower = min(from, through).clamped(to: bounds)
        let upper = max(from, through).clamped(to: bounds)
        let rows = lower...upper
        selection = DiffSelection(
            hunkID: hunk.id,
            fileName: fileName(forPath: hunk.filePath),
            rows: rows,
            lineNumbers: rows.compactMap { hunk.lines[$0].displayedNumber }
        )
    }

    func clearSelection() {
        selection = nil
    }

    // MARK: - Chat

    func closeChat() {
        isChatOpen = false
    }

    /// The panel with no hunk behind it: the agent introduces itself.
    /// No-ops when there is no agent — absence is absence.
    func openChat() {
        guard let agent = cannedAgent else { return }
        if thread == nil {
            thread = DiffChatThread(
                messages: [message(role: .agent, text: agent.openingMessage)]
            )
        }
        isChatOpen = true
    }

    /// Whether the file header's Explain control can produce an answer.
    /// Sample: canned hunk copy. Live: a real agent plus a text patch body for that path.
    func canExplainFile(_ file: DiffFile) -> Bool {
        if cannedAgent != nil {
            guard let hunk = file.hunks.first else { return canUseSampleAgent }
            return hunk.explanation != nil
        }
        return agent != nil && filePatchBodies[file.path] != nil
    }

    /// Whether the hunk's Explain / chat actions have an agent answer to show.
    func canExplain(_ hunk: DiffHunk) -> Bool {
        hunk.explanation != nil
    }

    /// Whether explaining the current selection can produce an agent answer.
    var canExplainSelection: Bool { cannedAgent != nil && selection != nil }

    /// Whether asking about the current selection can produce an agent answer.
    var canAskAboutSelection: Bool { cannedAgent != nil && selection != nil }

    /// The file header's chat button. Sample keeps the prototype path. Live asks the
    /// injected agent, with a one-deep queue and a completed cache per file.
    func explainFile(_ file: DiffFile) {
        if cannedAgent != nil {
            guard let hunk = file.hunks.first else {
                openChat()
                return
            }
            explain(hunk)
            return
        }
        enqueueAgentExplanation(for: file)
    }

    func explain(_ hunk: DiffHunk) {
        guard let explanation = hunk.explanation else { return }
        startThread(from: hunk, answering: explanation)
    }

    /// The marker on a hunk that carries an analysis note.
    func openNote(_ hunk: DiffHunk) {
        guard let note = hunk.note else { return }
        startThread(from: hunk, answering: note)
    }

    func explainSelection() {
        guard let agent = cannedAgent, let selection else { return }
        let reply = agent.explainSelectionReply(lineCountLabel: selection.lineCountLabel)
        self.selection = nil
        openThreadIfNeeded()
        think(reply: reply, location: selection.location, hunkID: nil)
    }

    /// The question typed into the selection popover. An empty one means the reader
    /// pressed send with nothing to add.
    func askAboutSelection(_ question: String) {
        guard let agent = cannedAgent, let selection else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            explainSelection()
            return
        }
        let location = selection.location
        self.selection = nil
        openThreadIfNeeded()
        append(message(role: .user, text: trimmed, location: location))
        think(
            reply: agent.selectionQuestionReply(location: location, question: trimmed),
            location: nil,
            hunkID: nil
        )
    }

    /// The composer at the bottom of the panel. No-ops without an agent.
    func send(_ text: String) {
        guard let agent = cannedAgent else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if thread == nil {
            thread = DiffChatThread(location: "\(compareBranch) → \(baseBranch)")
        }
        isChatOpen = true
        append(message(role: .user, text: trimmed))
        guard let reply = nextReply(fallback: agent.fallbackReply) else { return }
        think(reply: reply, location: nil, hunkID: nil)
    }

    /// The hunk the thread started from answers once; after that the agent has nothing
    /// canned left to say. `nil` when the hunk's reply is absent — do not invent one.
    private func nextReply(fallback: String) -> String? {
        guard
            let hunkID = thread?.hunkID,
            !usedHunkReplies.contains(hunkID),
            let hunk = hunk(withID: hunkID)
        else {
            return fallback
        }
        usedHunkReplies.insert(hunkID)
        return hunk.reply
    }

    // MARK: - Live agent explain (one-deep queue)

    private func enqueueAgentExplanation(for file: DiffFile) {
        guard agent != nil, filePatchBodies[file.path] != nil else { return }

        if let cached = completedFileExplanations[file.path] {
            presentCachedExplanation(path: file.path, text: cached)
            return
        }

        if inFlightExplainPath == file.path {
            openThreadIfNeeded()
            if let messageID = streamingMessageID ?? explanationMessageIDs[file.path] {
                requestChatScroll(to: messageID)
            }
            return
        }

        if inFlightExplainPath == nil {
            startAgentExplanation(path: file.path)
            return
        }

        // Running slot is busy — replace whoever was waiting. Never grow past one.
        queuedExplainPath = file.path
        openThreadIfNeeded()
    }

    private func presentCachedExplanation(path: String, text: String) {
        openThreadIfNeeded()
        if let messageID = explanationMessageIDs[path] {
            requestChatScroll(to: messageID)
            return
        }
        // Cache survived without a thread entry (should not happen in normal flow).
        let created = message(
            role: .agent,
            text: text,
            location: fileName(forPath: path)
        )
        explanationMessageIDs[path] = created.id
        append(created)
        requestChatScroll(to: created.id)
    }

    private func requestChatScroll(to messageID: Int) {
        chatScrollNonce &+= 1
        chatScrollRequest = DiffChatScrollRequest(messageID: messageID, nonce: chatScrollNonce)
    }

    /// The chat panel calls this after consuming a scroll request so a repeat click fires.
    func clearChatScrollRequest() {
        chatScrollRequest = nil
    }

    private func startAgentExplanation(path: String) {
        guard
            let agent,
            let patch = filePatchBodies[path],
            let repositoryRoot
        else {
            return
        }

        inFlightExplainPath = path
        queuedExplainPath = nil
        streamingMessageID = nil
        streamingFilePath = path

        openThreadIfNeeded()
        thread?.hunkID = nil
        thread?.location = fileName(forPath: path)
        // One entry per file — drop a prior incomplete/error bubble before streaming again.
        removeExplanationMessage(forPath: path)
        isThinking = true
        thinkingActivityLabel = nil

        let request = AgentExplainRequest(
            repositoryRoot: repositoryRoot,
            filePath: path,
            patch: patch,
            baseName: baseBranch,
            compareName: compareBranch,
            model: chatModel.agentModel,
            effort: reasoningEffort.agentEffort
        )

        let generation = explainGeneration
        pendingExplain?.cancel()
        pendingExplain = Task { [weak self] in
            await self?.consumeAgentExplanation(
                agent: agent,
                request: request,
                generation: generation
            )
        }
    }

    private func removeExplanationMessage(forPath path: String) {
        guard let messageID = explanationMessageIDs.removeValue(forKey: path) else { return }
        thread?.messages.removeAll { $0.id == messageID }
    }

    private func consumeAgentExplanation(
        agent: any DiffAgent,
        request: AgentExplainRequest,
        generation: Int
    ) async {
        var accumulated = ""
        var sawFinished = false

        do {
            for try await event in agent.explainFile(request) {
                guard !Task.isCancelled, generation == explainGeneration else {
                    finishAgentExplainSlot(cancelled: true, generation: generation)
                    return
                }
                switch event {
                case let .textDelta(delta):
                    accumulated += delta
                    appendStreamingDelta(accumulated)
                case let .toolStarted(command):
                    // Text may already be on screen; tools run silent for minutes without
                    // this — the panel must never look idle while the stream is alive.
                    thinkingActivityLabel = Self.readableToolActivity(command)
                    isThinking = true
                case .finished:
                    sawFinished = true
                }
            }
        } catch is CancellationError {
            finishAgentExplainSlot(cancelled: true, generation: generation)
            return
        } catch {
            guard !Task.isCancelled, generation == explainGeneration else {
                finishAgentExplainSlot(cancelled: true, generation: generation)
                return
            }
            presentAgentError(error)
            finishAgentExplainSlot(cancelled: false, generation: generation)
            return
        }

        guard !Task.isCancelled, generation == explainGeneration else {
            finishAgentExplainSlot(cancelled: true, generation: generation)
            return
        }

        // `.finished` is the only proof of a complete reply. Ending without it must
        // not be cached — and must not leave unmarked partial prose in the thread,
        // because a cut-off caveat reads as the opposite claim.
        if sawFinished {
            completedFileExplanations[request.filePath] = accumulated
            isThinking = false
            thinkingActivityLabel = nil
            if streamingMessageID == nil, !accumulated.isEmpty {
                appendStreamingDelta(accumulated)
            }
            if let streamingMessageID {
                explanationMessageIDs[request.filePath] = streamingMessageID
            }
        } else {
            presentAgentError(
                AgentError.failed(
                    reason: "The reply ended before it finished. This explanation is incomplete — ask again."
                )
            )
        }

        finishAgentExplainSlot(cancelled: false, generation: generation)
    }

    /// Short label for the thinking bubble — git verb, not a shell dump.
    static func readableToolActivity(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Working" }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens.first == "git", tokens.count >= 2 {
            return "Running git \(tokens[1])"
        }
        if let first = tokens.first {
            let short = first.count > 32 ? String(first.prefix(32)) + "…" : first
            return "Running \(short)"
        }
        return "Working"
    }

    private func appendStreamingDelta(_ text: String) {
        isThinking = false
        thinkingActivityLabel = nil
        let location = streamingFilePath.map(fileName(forPath:))
        if let streamingMessageID,
           let index = thread?.messages.firstIndex(where: { $0.id == streamingMessageID })
        {
            var messages = thread?.messages ?? []
            messages[index] = DiffChatMessage(
                id: streamingMessageID,
                role: .agent,
                text: text,
                location: location,
                hunkID: nil
            )
            thread?.messages = messages
            return
        }

        let created = message(role: .agent, text: text, location: location)
        streamingMessageID = created.id
        if let streamingFilePath {
            explanationMessageIDs[streamingFilePath] = created.id
        }
        append(created)
    }

    private func presentAgentError(_ error: Error) {
        isThinking = false
        thinkingActivityLabel = nil
        let text: String
        if let agentError = error as? AgentError {
            text = agentError.errorDescription ?? String(describing: agentError)
        } else {
            text = error.localizedDescription
        }
        let location = streamingFilePath.map(fileName(forPath:))
        openThreadIfNeeded()
        // Replace only this file's bubble — earlier explanations in the thread stay.
        if let messageID = streamingMessageID,
           let index = thread?.messages.firstIndex(where: { $0.id == messageID })
        {
            var messages = thread?.messages ?? []
            messages[index] = DiffChatMessage(
                id: messageID,
                role: .agent,
                text: text,
                location: location,
                hunkID: nil
            )
            thread?.messages = messages
            if let streamingFilePath {
                explanationMessageIDs[streamingFilePath] = messageID
            }
            streamingMessageID = nil
            return
        }

        if let streamingFilePath {
            removeExplanationMessage(forPath: streamingFilePath)
            let created = message(role: .agent, text: text, location: location)
            explanationMessageIDs[streamingFilePath] = created.id
            append(created)
        } else {
            append(message(role: .agent, text: text, location: location))
        }
        streamingMessageID = nil
    }

    private func finishAgentExplainSlot(cancelled: Bool, generation: Int) {
        guard generation == explainGeneration else { return }
        let next = cancelled ? nil : queuedExplainPath
        inFlightExplainPath = nil
        queuedExplainPath = nil
        streamingMessageID = nil
        streamingFilePath = nil
        pendingExplain = nil
        if cancelled {
            isThinking = false
            thinkingActivityLabel = nil
            return
        }
        if let next {
            startAgentExplanation(path: next)
        }
    }

    private func cancelAgentExplain(clearQueue: Bool) {
        explainGeneration += 1
        pendingExplain?.cancel()
        pendingExplain = nil
        inFlightExplainPath = nil
        if clearQueue {
            queuedExplainPath = nil
        }
        streamingMessageID = nil
        streamingFilePath = nil
        isThinking = false
        thinkingActivityLabel = nil
    }

    private func startThread(from hunk: DiffHunk, answering text: String) {
        openThreadIfNeeded()
        thread?.hunkID = hunk.id
        think(reply: text, location: hunk.location, hunkID: hunk.id)
    }

    private func openThreadIfNeeded() {
        if thread == nil {
            thread = DiffChatThread()
        }
        isChatOpen = true
    }

    private func think(reply: String, location: String?, hunkID: String?) {
        pendingReply?.cancel()
        isThinking = true
        pendingReply = Task { [weak self] in
            do {
                try await self?.replyDelay.wait()
            } catch {
                // The only way out of the wait is cancellation, and a cancelled round
                // trip has no answer to deliver.
                return
            }
            guard !Task.isCancelled, let self else { return }
            isThinking = false
            append(message(role: .agent, text: reply, location: location, hunkID: hunkID))
        }
    }

    private func append(_ message: DiffChatMessage) {
        guard thread != nil else {
            preconditionFailure("A message was appended before a thread existed.")
        }
        thread?.messages.append(message)
    }

    private func message(
        role: DiffChatRole,
        text: String,
        location: String? = nil,
        hunkID: String? = nil
    ) -> DiffChatMessage {
        defer { nextMessageID += 1 }
        return DiffChatMessage(
            id: nextMessageID,
            role: role,
            text: text,
            location: location,
            hunkID: hunkID
        )
    }

    // MARK: - Leaving

    /// Reading is about one diff. Going back to Welcome ends it, so nothing is carried
    /// into the next one. Cancels an in-flight patch load the same way Welcome cancels
    /// its git tasks.
    func returnToWelcome() {
        pendingLoad?.cancel()
        pendingLoad = nil
        loadGeneration += 1

        pendingReply?.cancel()
        pendingReply = nil
        cancelAgentExplain(clearQueue: true)
        completedFileExplanations = [:]
        explanationMessageIDs = [:]
        filePatchBodies = [:]
        repositoryRoot = nil
        chatScrollRequest = nil

        if usesSampleData {
            viewedPaths = DiffSampleData.defaultViewedPaths
            collapsedPaths = DiffSampleData.defaultViewedPaths
        } else {
            files = []
            sectionFiles = []
            viewedPaths = []
            collapsedPaths = []
            compareBranch = ""
            baseBranch = ""
            repositoryName = ""
            declaredFileCount = 0
            declaredAdditions = 0
            declaredDeletions = 0
            declaredTotalHunkCount = 0
            loadState = .loading
            refreshFilterCaches()
        }

        readHunkIDs = []
        selection = nil
        focusedFilePath = nil
        readerScrollRequest = nil
        isChatOpen = false
        thread = nil
        isThinking = false
        thinkingActivityLabel = nil
        usedHunkReplies = []
        closedDirectories = []
        refreshViewedDirectoryStates()
        refreshReadProgress()
    }

    // MARK: - Caches

    private func refreshFilterCaches() {
        filterCacheRefreshCount += 1
        let needle = normalizedFilter
        if needle.isEmpty {
            filteredFiles = files
        } else {
            filteredFiles = files.filter { $0.path.lowercased().contains(needle) }
        }
        fileTree = DiffTree.build(files: filteredFiles)
        refreshViewedDirectoryStates()
    }

    /// One bottom-up walk of `fileTree`. Sidebar rows then read O(1) from the map.
    private func refreshViewedDirectoryStates() {
        directoryViewedStateRefreshCount += 1
        var states: [String: DiffAggregateState] = [:]

        @discardableResult
        func walk(_ nodes: [DiffTreeNode]) -> (matching: Int, total: Int) {
            var matching = 0
            var total = 0
            for node in nodes {
                switch node {
                case let .file(file, _):
                    total += 1
                    if viewedPaths.contains(file.path) { matching += 1 }
                case let .directory(directory):
                    let child = walk(directory.children)
                    states[directory.path] = DiffAggregateState.of(
                        matchingCount: child.matching,
                        total: child.total
                    )
                    matching += child.matching
                    total += child.total
                }
            }
            return (matching, total)
        }

        _ = walk(fileTree)
        directoryViewedStates = states
    }

    private func refreshReadProgress() {
        readProgressRefreshCount += 1
        readHunkCount = readHunkBaseline + sectionHunks.filter { isRead($0) }.count
    }

    // MARK: - Lookup

    func hunk(withID id: String) -> DiffHunk? {
        sectionHunks.first { $0.id == id }
    }

    func file(atPath path: String) -> DiffFile? {
        files.first { $0.path == path }
    }

    private func fileName(forPath path: String) -> String {
        file(atPath: path)?.name ?? path
    }
}

private extension Int {
    func clamped(to bounds: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, bounds.lowerBound), bounds.upperBound)
    }
}
