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

    init(milliseconds: ClosedRange<Int> = DiffSampleData.replyDelayRange) {
        self.milliseconds = milliseconds
    }

    func wait() async throws {
        try await Task.sleep(for: .milliseconds(Int.random(in: milliseconds)))
    }
}

/// State of the diff screen. Every rule — what viewed implies, what counts as read,
/// what a selection is called, what the agent answers — lives here, so the views stay a
/// rendering of this object and nothing else.
@MainActor
@Observable
final class DiffModel {
    let files: [DiffFile]
    /// The files the center viewer shows, in its own order.
    let sectionFiles: [DiffFile]

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
    var chatModel = DiffSampleData.defaultChatModel
    var reasoningEffort = DiffSampleData.defaultReasoningEffort
    /// The copy the panel cycles while an answer is on its way, so the view never has
    /// to reach into the sample data itself.
    let thinkingIndicator = DiffSampleData.thinkingIndicator
    /// The fake round trip currently in flight. Tests await it instead of sleeping.
    private(set) var pendingReply: Task<Void, Never>?

    private let replyDelay: DiffReplyDelay
    /// Hunks already read before this sample, so the progress starts where the diff does.
    private let readHunkBaseline: Int
    private var closedDirectories: Set<String> = []
    private var usedHunkReplies: Set<String> = []
    private var nextMessageID = 0

    init(
        replyDelay: DiffReplyDelay = RandomDiffReplyDelay(),
        readHunkBaseline: Int = DiffSampleData.readHunkBaseline
    ) {
        self.replyDelay = replyDelay
        self.readHunkBaseline = readHunkBaseline
        files = DiffSampleData.files
        sectionFiles = DiffSampleData.sectionFiles
        viewedPaths = DiffSampleData.defaultViewedPaths
        collapsedPaths = DiffSampleData.defaultViewedPaths
    }

    // MARK: - Headline

    var compareBranch: String { DiffSampleData.compareBranch }
    var baseBranch: String { DiffSampleData.baseBranch }

    // These describe the whole diff, not the sample in `files`, so the top bar agrees
    // with the count the Welcome screen promised.
    var fileCountText: String { "\(DiffSampleData.declaredFileCount) files" }
    var additionsText: String { "+\(DiffSampleData.declaredAdditions)" }
    var deletionsText: String { "\(DiffFormat.minusSign)\(DiffSampleData.declaredDeletions)" }

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

    var totalHunkCount: Int { DiffSampleData.totalHunkCount }

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
    func openChat() {
        if thread == nil {
            thread = DiffChatThread(
                messages: [message(role: .agent, text: DiffSampleData.openingAgentMessage)]
            )
        }
        isChatOpen = true
    }

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
        startThread(from: hunk, answering: hunk.explanation)
    }

    /// The marker on a hunk that carries an analysis note.
    func openNote(_ hunk: DiffHunk) {
        guard let note = hunk.note else { return }
        startThread(from: hunk, answering: note)
    }

    func explainSelection() {
        guard let selection else { return }
        let reply = DiffSampleData.explainSelectionReply(lineCountLabel: selection.lineCountLabel)
        self.selection = nil
        openThreadIfNeeded()
        think(reply: reply, location: selection.location, hunkID: nil)
    }

    /// The question typed into the selection popover. An empty one means the reader
    /// pressed send with nothing to add.
    func askAboutSelection(_ question: String) {
        guard let selection else { return }
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
            reply: DiffSampleData.selectionQuestionReply(location: location, question: trimmed),
            location: nil,
            hunkID: nil
        )
    }

    /// The composer at the bottom of the panel.
    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if thread == nil {
            thread = DiffChatThread(location: DiffSampleData.threadLocation)
        }
        isChatOpen = true
        append(message(role: .user, text: trimmed))
        think(reply: nextReply(), location: nil, hunkID: nil)
    }

    /// The hunk the thread started from answers once; after that the agent has nothing
    /// canned left to say.
    private func nextReply() -> String {
        guard
            let hunkID = thread?.hunkID,
            !usedHunkReplies.contains(hunkID),
            let hunk = hunk(withID: hunkID)
        else {
            return DiffSampleData.fallbackReply
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
    /// into the next one.
    func returnToWelcome() {
        pendingReply?.cancel()
        pendingReply = nil
        viewedPaths = DiffSampleData.defaultViewedPaths
        collapsedPaths = DiffSampleData.defaultViewedPaths
        readHunkIDs = []
        selection = nil
        isChatOpen = false
        thread = nil
        isThinking = false
        usedHunkReplies = []
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
