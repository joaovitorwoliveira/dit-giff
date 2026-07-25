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
    /// `nil` in a live session. The structural guarantee that live code never reads
    /// canned agent copy: there is no handle to reach it.
    private let cannedAgent: DiffCannedAgent?

    // MARK: - Load

    private(set) var loadState: DiffLoadState
    /// The in-flight patch load. Tests await or cancel it instead of racing the clock.
    private(set) var pendingLoad: Task<Void, Never>?
    /// Bumped on every load start and on return-to-Welcome so a stale task cannot write.
    private var loadGeneration = 0

    // MARK: - Sidebar

    var filter = ""
    private(set) var isSidebarOpen = true

    // MARK: - Reading state

    private(set) var viewedPaths: Set<String>
    private(set) var collapsedPaths: Set<String>
    private(set) var readHunkIDs: Set<String> = []

    // MARK: - Selection

    private(set) var selection: DiffSelection?

    // MARK: - Chat

    private(set) var isChatOpen = false
    private(set) var thread: DiffChatThread?
    private(set) var isThinking = false
    var chatModel: DiffChatModelOption
    var reasoningEffort: DiffReasoningEffort
    /// The fake round trip currently in flight. Tests await it instead of sleeping.
    private(set) var pendingReply: Task<Void, Never>?

    private let replyDelay: DiffReplyDelay
    /// Hunks already read before this sample, so the progress starts where the diff does.
    /// Zero for a live session — only the hunks on screen count.
    private var readHunkBaseline: Int
    private var closedDirectories: Set<String> = []
    private var usedHunkReplies: Set<String> = []
    private var nextMessageID = 0

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
    }

    /// Live construction — empty until `load(_:)` runs. No canned agent: every path that
    /// would invent a reply has nowhere to get one.
    init(
        git: GitService,
        replyDelay: DiffReplyDelay = NullDiffReplyDelay()
    ) {
        self.replyDelay = replyDelay
        self.readHunkBaseline = 0
        self.git = git
        self.usesSampleData = false
        self.cannedAgent = nil
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
    }

    // MARK: - Agent availability

    /// Whether any agent answer source exists. Live sessions are `false` until Slice 4.
    var canUseAgent: Bool { cannedAgent != nil }

    /// The thinking chrome. Absent when there is no agent — the panel must not invent words.
    var thinkingIndicator: DiffThinkingIndicator? { cannedAgent?.thinkingIndicator }

    /// Selection popover actions all need an agent. If none, the popover must not appear.
    var canPresentSelectionPopover: Bool { canUseAgent }

    /// General chat (open + composer) needs an agent. Live sessions keep the panel closed.
    var canOpenChat: Bool { canUseAgent }

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
        files = []
        sectionFiles = []
        viewedPaths = []
        collapsedPaths = []
        readHunkIDs = []
        selection = nil
        closedDirectories = []
        declaredFileCount = 0
        declaredAdditions = 0
        declaredDeletions = 0
        declaredTotalHunkCount = 0
        loadState = .loading

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
        loadState = .loaded
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

    var filteredFiles: [DiffFile] {
        let needle = normalizedFilter
        guard !needle.isEmpty else { return files }
        return files.filter { $0.path.lowercased().contains(needle) }
    }

    /// Built from the files that matched, so a folder survives exactly as long as one of
    /// its files does.
    var fileTree: [DiffTreeNode] {
        DiffTree.build(files: filteredFiles)
    }

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
        guard isViewed else {
            viewedPaths.remove(file.path)
            collapsedPaths.remove(file.path)
            return
        }
        viewedPaths.insert(file.path)
        collapsedPaths.insert(file.path)
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
            return
        }
        readHunkIDs.remove(hunk.id)
        guard let file = file(atPath: hunk.filePath) else { return }
        setViewed(false, for: file)
    }

    private var sectionHunks: [DiffHunk] {
        sectionFiles.flatMap(\.hunks)
    }

    var readHunkCount: Int {
        readHunkBaseline + sectionHunks.filter { isRead($0) }.count
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

    /// Whether the file header's Explain control has an agent answer to show.
    /// A file with no hunk opens the general thread — only when an agent exists.
    func canExplainFile(_ file: DiffFile) -> Bool {
        guard let hunk = file.hunks.first else { return canUseAgent }
        return hunk.explanation != nil
    }

    /// Whether the hunk's Explain / chat actions have an agent answer to show.
    func canExplain(_ hunk: DiffHunk) -> Bool {
        hunk.explanation != nil
    }

    /// Whether explaining the current selection can produce an agent answer.
    var canExplainSelection: Bool { canUseAgent && selection != nil }

    /// Whether asking about the current selection can produce an agent answer.
    var canAskAboutSelection: Bool { canUseAgent && selection != nil }

    /// The file header's chat button. A file with no hunk in the viewer has nothing
    /// specific to explain, so it opens the general thread.
    func explainFile(_ file: DiffFile) {
        guard let hunk = file.hunks.first else {
            openChat()
            return
        }
        explain(hunk)
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
        }

        readHunkIDs = []
        selection = nil
        isChatOpen = false
        thread = nil
        isThinking = false
        usedHunkReplies = []
        closedDirectories = []
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
