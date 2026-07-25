import Foundation
import Observation

/// A row in the recent list. Availability is checked here — the store never looks at disk.
/// `headLabel` is read live from git when the row is available; it is never stored in JSON.
nonisolated struct WelcomeRecentEntry: Identifiable, Equatable, Sendable {
    let rootPath: String
    let displayName: String
    let lastOpenedAt: Date
    let isAvailable: Bool
    /// Branch name, `"detached HEAD"`, or `nil` while loading / on read failure / when missing.
    let headLabel: String?

    var id: String { rootPath }
}

/// A dismissible notice on Welcome. Optional action removes a missing recent entry.
nonisolated struct WelcomeBanner: Equatable, Sendable {
    let message: String
    let actionTitle: String?
    let actionRootPath: String?

    init(message: String, actionTitle: String? = nil, actionRootPath: String? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.actionRootPath = actionRootPath
    }
}

/// State of the Welcome screen. Every rule about what a selection implies lives here,
/// so the view stays a rendering of this object and nothing else.
@MainActor
@Observable
final class WelcomeModel {
    private let git: GitService
    private let recentStore: RecentRepositoriesStore
    private let directoryPicker: DirectoryPicker
    private let fileManager: FileManager

    private(set) var recentRepositories: [WelcomeRecentEntry] = []
    private(set) var selectedRepository: GitRepository?
    private(set) var branches: [GitBranch] = []
    private(set) var baseBranch: GitBranch?
    private(set) var compareBranch: GitBranch?

    /// Loaded file-count label, or the loading / empty stand-ins. Never a lying zero.
    private(set) var changeSummary = WelcomeSampleData.unknownChangeSummary
    private(set) var isCountingChanges = false
    private(set) var isOpeningRepository = false
    private(set) var isFetching = false
    private(set) var isDropTargeted = false
    private(set) var banner: WelcomeBanner?

    var goal = ""
    private(set) var attachedSpecName: String?

    /// Bumped on every repository switch or clear. Async work captures the value and
    /// only writes state when it still matches — same idea as the change-count generation,
    /// for the whole selection.
    private var repositorySession = 0
    private var openTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var changeCountTask: Task<Void, Never>?
    private var recentHeadsTask: Task<Void, Never>?
    /// Bumped when the selected pair changes within one repository session.
    private var changeCountGeneration = 0
    /// Bumped on every recents reload so in-flight HEAD reads cannot write a stale list.
    private var recentHeadsGeneration = 0

    var canOpenDiff: Bool {
        selectedRepository != nil && baseBranch != nil && compareBranch != nil
    }

    var branchDisplayNames: [String] {
        branches.map(\.displayName)
    }

    init(
        git: GitService,
        recentStore: RecentRepositoriesStore,
        directoryPicker: DirectoryPicker,
        fileManager: FileManager = .default
    ) {
        self.git = git
        self.recentStore = recentStore
        self.directoryPicker = directoryPicker
        self.fileManager = fileManager
        reloadRecents()
    }

    // MARK: - Recents

    func reloadRecents() {
        do {
            let stored = try recentStore.load()
            recentRepositories = stored.map { entry in
                WelcomeRecentEntry(
                    rootPath: entry.rootPath,
                    displayName: entry.displayName,
                    lastOpenedAt: entry.lastOpenedAt,
                    isAvailable: fileManager.fileExists(atPath: entry.rootPath),
                    headLabel: nil
                )
            }
            scheduleRecentHeadLoads()
        } catch {
            recentRepositories = []
            present(error)
        }
    }

    func selectRecent(_ entry: WelcomeRecentEntry) {
        dismissBanner()
        guard entry.isAvailable else {
            let url = URL(fileURLWithPath: entry.rootPath, isDirectory: true)
            banner = WelcomeBanner(
                message: GitError.repositoryMovedOrDeleted(url).errorDescription
                    ?? "That repository is no longer where it was.",
                actionTitle: "Remove from list",
                actionRootPath: entry.rootPath
            )
            return
        }
        let url = URL(fileURLWithPath: entry.rootPath, isDirectory: true)
        openTask?.cancel()
        openTask = Task { await openRepository(at: url) }
    }

    func removeRecent(rootPath: String) {
        do {
            try recentStore.remove(rootPath: rootPath)
            reloadRecents()
            dismissBanner()
        } catch {
            present(error)
        }
    }

    // MARK: - Open

    func chooseRepository() {
        openTask?.cancel()
        openTask = Task {
            guard let url = await directoryPicker.pickDirectory() else { return }
            await openRepository(at: url)
        }
    }

    func openDroppedFolder(at url: URL) async {
        await openRepository(at: url)
    }

    func reportDropFailure(_ message: String) {
        banner = WelcomeBanner(message: message)
    }

    func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
    }

    func openRepository(at url: URL) async {
        beginRepositorySession()
        let session = repositorySession
        dismissBanner()
        clearSelectionState()
        isOpeningRepository = true
        defer {
            if sessionIsCurrent(session) {
                isOpeningRepository = false
            }
        }

        do {
            let repository = try await git.openRepository(at: url)
            guard sessionIsCurrent(session) else { return }

            try recentStore.record(
                rootPath: repository.rootURL.path,
                displayName: repository.displayName
            )
            guard sessionIsCurrent(session) else { return }
            reloadRecents()

            let selection = try await loadSelection(for: repository)
            guard sessionIsCurrent(session) else { return }

            selectedRepository = repository
            branches = selection.branches
            baseBranch = selection.base
            compareBranch = selection.compare
            refreshChangeCount()
        } catch {
            guard sessionIsCurrent(session) else { return }
            present(error)
        }
    }

    func clearRepository() {
        openTask?.cancel()
        openTask = nil
        beginRepositorySession()
        isOpeningRepository = false
        clearSelectionState()
        goal = ""
        attachedSpecName = nil
        dismissBanner()
    }

    // MARK: - Branches

    func selectCompare(displayName: String?) {
        compareBranch = branch(named: displayName)
        refreshChangeCount()
    }

    func selectBase(displayName: String?) {
        guard let displayName, let branch = branch(named: displayName) else { return }
        baseBranch = branch
        refreshChangeCount()
    }

    // MARK: - Fetch

    func fetch() {
        guard let repository = selectedRepository, !isFetching else { return }
        let session = repositorySession
        dismissBanner()
        isFetching = true
        fetchTask?.cancel()
        fetchTask = Task {
            defer {
                if sessionIsCurrent(session) {
                    isFetching = false
                }
            }
            await performFetch(in: repository, session: session)
        }
    }

    // MARK: - Session

    func makeSession() -> DiffSession? {
        guard let repository = selectedRepository,
              let base = baseBranch,
              let compare = compareBranch
        else { return nil }
        return DiffSession(
            repository: repository,
            base: base,
            compare: compare,
            goal: goal,
            attachedSpecName: attachedSpecName
        )
    }

    // MARK: - Goal / spec (still mock — Slice 5)

    func attachSpec() {
        attachedSpecName = WelcomeSampleData.sampleSpecName
    }

    func removeSpec() {
        attachedSpecName = nil
    }

    func dismissBanner() {
        banner = nil
    }

    func performBannerAction() {
        guard let rootPath = banner?.actionRootPath else {
            dismissBanner()
            return
        }
        removeRecent(rootPath: rootPath)
    }

    // MARK: - Internals

    private struct BranchSelection {
        let branches: [GitBranch]
        let base: GitBranch?
        let compare: GitBranch?
    }

    /// Loads a coherent branch selection without touching `selectedRepository`.
    private func loadSelection(for repository: GitRepository) async throws -> BranchSelection {
        let listed = try await git.listBranches(in: repository)
        let originHEAD = try await git.originHEADRef(in: repository)
        let currentName: String?
        if case let .branch(name) = repository.head {
            currentName = name
        } else {
            currentName = nil
        }
        let base = GitBaseSelection.probableBase(
            among: listed,
            originHEADRef: originHEAD,
            currentBranchName: currentName
        )
        let compare: GitBranch?
        if let currentName,
           let current = listed.first(where: { $0.name == currentName && $0.remote == nil }),
           current.fullRef != base?.fullRef
        {
            compare = current
        } else {
            compare = nil
        }
        return BranchSelection(branches: listed, base: base, compare: compare)
    }

    private func performFetch(in repository: GitRepository, session: Int) async {
        do {
            try await git.fetch(in: repository)
            guard sessionIsCurrent(session) else { return }

            let previousBase = baseBranch?.fullRef
            let previousCompare = compareBranch?.fullRef
            let listed = try await git.listBranches(in: repository)
            guard sessionIsCurrent(session) else { return }

            branches = listed
            // A pruned base must not linger as a ghost selection outside the menu.
            baseBranch = listed.first { $0.fullRef == previousBase }
            compareBranch = listed.first { $0.fullRef == previousCompare }

            if baseBranch == nil {
                let originHEAD = try await git.originHEADRef(in: repository)
                guard sessionIsCurrent(session) else { return }
                let currentName: String?
                if case let .branch(name) = repository.head {
                    currentName = name
                } else {
                    currentName = nil
                }
                baseBranch = GitBaseSelection.probableBase(
                    among: listed,
                    originHEADRef: originHEAD,
                    currentBranchName: currentName
                )
            }
            refreshChangeCount()
        } catch {
            guard sessionIsCurrent(session) else { return }
            present(error)
        }
    }

    private func refreshChangeCount() {
        changeCountTask?.cancel()
        changeCountGeneration += 1
        let generation = changeCountGeneration
        let session = repositorySession

        guard let repository = selectedRepository,
              let base = baseBranch,
              let compare = compareBranch
        else {
            isCountingChanges = false
            changeSummary = WelcomeSampleData.unknownChangeSummary
            changeCountTask = nil
            return
        }

        isCountingChanges = true
        changeSummary = WelcomeSampleData.countingChangeSummary

        changeCountTask = Task { [git] in
            do {
                let count = try await git.changedFileCount(
                    in: repository,
                    base: base,
                    compare: compare
                )
                guard !Task.isCancelled,
                      generation == changeCountGeneration,
                      sessionIsCurrent(session)
                else { return }
                changeSummary = Self.changeSummaryLabel(for: count)
                isCountingChanges = false
            } catch is CancellationError {
                // Replaced by a newer count — leave the loading state to that task.
            } catch {
                guard !Task.isCancelled,
                      generation == changeCountGeneration,
                      sessionIsCurrent(session)
                else { return }
                isCountingChanges = false
                changeSummary = WelcomeSampleData.unknownChangeSummary
                present(error)
            }
        }
    }

    private func beginRepositorySession() {
        repositorySession += 1
        // Do not cancel `openTask` here — this method runs inside an open. Callers that
        // start a newer open cancel the previous task themselves.
        // Do not cancel `recentHeadsTask` here either — a failed open would leave the
        // list without a reload; stale HEAD writes are blocked by sessionIsCurrent.
        fetchTask?.cancel()
        changeCountTask?.cancel()
        fetchTask = nil
        changeCountTask = nil
        changeCountGeneration += 1
        isFetching = false
        isCountingChanges = false
    }

    /// Live HEAD labels for available recents. Captures both the recents generation and
    /// the repository session so a switch/clear cannot be overwritten by a late read.
    private func scheduleRecentHeadLoads() {
        recentHeadsTask?.cancel()
        recentHeadsGeneration += 1
        let generation = recentHeadsGeneration
        let session = repositorySession
        let targets = recentRepositories.filter(\.isAvailable)

        recentHeadsTask = Task { [git] in
            for entry in targets {
                guard !Task.isCancelled,
                      generation == recentHeadsGeneration,
                      sessionIsCurrent(session)
                else { return }

                let url = URL(fileURLWithPath: entry.rootPath, isDirectory: true)
                let label: String?
                do {
                    label = try await git.currentHEAD(at: url).listLabel
                } catch {
                    // Not a user-requested action — leave the row without a branch.
                    label = nil
                }

                guard !Task.isCancelled,
                      generation == recentHeadsGeneration,
                      sessionIsCurrent(session)
                else { return }

                guard let index = recentRepositories.firstIndex(where: { $0.rootPath == entry.rootPath })
                else { continue }
                let current = recentRepositories[index]
                recentRepositories[index] = WelcomeRecentEntry(
                    rootPath: current.rootPath,
                    displayName: current.displayName,
                    lastOpenedAt: current.lastOpenedAt,
                    isAvailable: current.isAvailable,
                    headLabel: label
                )
            }
        }
    }

    private func clearSelectionState() {
        selectedRepository = nil
        branches = []
        baseBranch = nil
        compareBranch = nil
        changeSummary = WelcomeSampleData.unknownChangeSummary
    }

    private func sessionIsCurrent(_ session: Int) -> Bool {
        session == repositorySession
    }

    private func branch(named displayName: String?) -> GitBranch? {
        guard let displayName else { return nil }
        return branches.first { $0.displayName == displayName }
    }

    private func present(_ error: Error) {
        if let gitError = error as? GitError {
            banner = WelcomeBanner(message: gitError.errorDescription ?? String(describing: gitError))
            return
        }
        if let storeError = error as? RecentRepositoriesStoreError {
            banner = WelcomeBanner(message: storeError.errorDescription ?? String(describing: storeError))
            return
        }
        banner = WelcomeBanner(message: error.localizedDescription)
    }

    private static func changeSummaryLabel(for count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }
}
