import Foundation

extension DiffModel {
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
}
