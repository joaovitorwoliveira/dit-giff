import Foundation

extension DiffModel {
    // MARK: - Sidebar

    func toggleSidebar() {
        isSidebarOpen.toggle()
    }

    var normalizedFilter: String {
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

    func setViewed(_ isViewed: Bool, for file: DiffFile) {
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
}
