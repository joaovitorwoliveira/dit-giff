import Foundation
import Observation

/// State of the diff screen. Every rule — what viewed implies, what counts as read,
/// what a selection is called, what the agent answers — lives here, so the views stay a
/// rendering of this object and nothing else.
@MainActor
@Observable
final class DiffModel {
    var files: [DiffFile]
    /// The files the center viewer shows, in its own order.
    var sectionFiles: [DiffFile]

    /// Sample data for previews and unit tests, or a live session driven by git.
    let usesSampleData: Bool
    let git: GitService?
    /// Sample/preview only. A live session never holds one — that is what keeps
    /// DiffSampleData copy unreachable from real diffs.
    let cannedAgent: DiffCannedAgent?
    /// Live AI seam. Nil in sample mode and in live sessions that have no agent yet.
    let agent: (any DiffAgent)?
    /// Persists reading marks across relaunches. Nil in sample mode and in live
    /// sessions constructed without a store (most unit tests).
    let readingProgressStore: (any ReadingProgressStoring)?

    // MARK: - Load

    var loadState: DiffLoadState
    /// The in-flight patch load. Tests await or cancel it instead of racing the clock.
    var pendingLoad: Task<Void, Never>?
    /// Bumped on every load start and on return-to-Welcome so a stale task cannot write.
    var loadGeneration = 0
    /// Per-file unified body from the last loaded `Patch`. Keyed by destination path.
    /// Text only — used by Explain and by reading fingerprints.
    var filePatchBodies: [String: String] = [:]
    /// Per-hunk unified slice from the last loaded `Patch`. Keyed by `DiffHunk.id`.
    var hunkPatchBodies: [String: String] = [:]
    /// Per-file raw header from the last loaded `Patch`. Non-text fingerprints only —
    /// kept out of `filePatchBodies` so Explain stays off for binary/submodule/no-content.
    var filePatchHeaders: [String: String] = [:]
    var repositoryRoot: URL?
    /// Canonical refs for the progress store. Display names stay in `baseBranch` /
    /// `compareBranch` — different data, different purpose.
    var progressKey: ReadingProgressKey?
    /// Surfaced when a progress save or restore fails. Presentable; clear with
    /// `clearReadingProgressError()`.
    var readingProgressError: String?

    // MARK: - Sidebar

    var filter = "" {
        didSet {
            guard filter != oldValue else { return }
            refreshFilterCaches()
        }
    }
    var isSidebarOpen = true
    /// Cached from `files` + `filter`. Invalidated only when either changes.
    private(set) var filteredFiles: [DiffFile] = []
    /// Cached tree of `filteredFiles`. Invalidated with the filter caches.
    private(set) var fileTree: [DiffTreeNode] = []
    /// Test seam: how often the filter / tree caches were rebuilt.
    private(set) var filterCacheRefreshCount = 0

    // MARK: - Reading state

    var viewedPaths: Set<String>
    var collapsedPaths: Set<String>
    var readHunkIDs: Set<String> = []
    /// Cached progress. Invalidated when viewed / read / section files / baseline change.
    private(set) var readHunkCount: Int = 0
    /// Test seam: how often progress was recomputed.
    private(set) var readProgressRefreshCount = 0
    /// Directory path → viewed aggregate over all descendants. Rebuilt with viewed / tree.
    private(set) var directoryViewedStates: [String: DiffAggregateState] = [:]
    /// Test seam: how often directory viewed aggregates were recomputed.
    private(set) var directoryViewedStateRefreshCount = 0

    // MARK: - Selection

    var selection: DiffSelection?

    // MARK: - Sidebar → reader navigation

    /// The change-map tree line under the keyboard cursor — a file path, or a
    /// directory path ending in `/`. Highlight only — not the same as viewed.
    var focusedFilePath: String?
    /// Consumed by the viewer to animate a scroll. `nil` when idle.
    var readerScrollRequest: DiffReaderScrollRequest?
    var readerScrollNonce: UInt = 0

    // MARK: - Chat

    var isChatOpen = false
    var thread: DiffChatThread?
    var isThinking = false
    /// Overrides the cycling thinking words while a tool is running — keeps the panel
    /// alive when the agent is silent between text deltas.
    var thinkingActivityLabel: String?
    /// Consumed by the chat panel to scroll to an existing explanation.
    var chatScrollRequest: DiffChatScrollRequest?
    var chatScrollNonce: UInt = 0
    var chatModel: DiffChatModelOption
    var reasoningEffort: DiffReasoningEffort
    /// The fake round trip currently in flight. Tests await it instead of sleeping.
    var pendingReply: Task<Void, Never>?
    /// The live explain currently in flight (running slot of the one-deep queue).
    var pendingExplain: Task<Void, Never>?

    let replyDelay: DiffReplyDelay
    /// Hunks already read before this sample, so the progress starts where the diff does.
    /// Zero for a live session — only the hunks on screen count.
    var readHunkBaseline: Int
    var closedDirectories: Set<String> = []
    var usedHunkReplies: Set<String> = []
    var nextMessageID = 0
    /// Completed explanations only — a stream without `.finished` never lands here.
    var completedExplanations: [AgentExplainTarget: String] = [:]
    /// One thread entry per explain target — used to scroll back and to enforce uniqueness.
    var explanationMessageIDs: [AgentExplainTarget: Int] = [:]
    var inFlightExplainTarget: AgentExplainTarget?
    /// At most one waiter. A newer request replaces whoever was waiting.
    var queuedExplainTarget: AgentExplainTarget?
    var streamingMessageID: Int?
    var streamingExplainTarget: AgentExplainTarget?
    /// Bumped when explains are cancelled so a stale task cannot start the queue.
    var explainGeneration = 0

    // MARK: - Headline (session / sample)

    var compareBranch: String
    var baseBranch: String
    var repositoryName: String
    var declaredFileCount: Int
    var declaredAdditions: Int
    var declaredDeletions: Int
    var declaredTotalHunkCount: Int

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
        self.readingProgressStore = nil
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
        replyDelay: DiffReplyDelay = NullDiffReplyDelay(),
        readingProgressStore: (any ReadingProgressStoring)? = nil
    ) {
        self.replyDelay = replyDelay
        self.readHunkBaseline = 0
        self.git = git
        self.usesSampleData = false
        self.cannedAgent = nil
        self.agent = agent
        self.readingProgressStore = readingProgressStore
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

    // MARK: - Caches

    func refreshFilterCaches() {
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
    func refreshViewedDirectoryStates() {
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

    func refreshReadProgress() {
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

    func fileName(forPath path: String) -> String {
        file(atPath: path)?.name ?? path
    }

}

extension Int {
    func clamped(to bounds: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, bounds.lowerBound), bounds.upperBound)
    }
}
