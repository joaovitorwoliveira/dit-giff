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
        } else {
            closedDirectories.insert(path)
        }
        persistReadingProgress()
    }

    /// Opens every closed ancestor of `filePath` so the focused file has a row to
    /// scroll to. Used by `n` (explicit unread jump) and progress restore — never by
    /// ←/→ / Shift+↑↓, which must leave closed folders closed.
    @discardableResult
    func ensureAncestorDirectoriesOpen(forFilePath filePath: String) -> Bool {
        let components = filePath.split(separator: "/")
        guard components.count > 1 else { return false }
        var prefix = ""
        var changed = false
        for component in components.dropLast() {
            prefix += "\(component)/"
            if closedDirectories.remove(prefix) != nil {
                changed = true
            }
        }
        if changed {
            persistReadingProgress()
        }
        return changed
    }

    // MARK: - Keyboard folder navigation

    /// Shift+↓ — jump to the next folder **line**. Does not open closed folders and
    /// does not scroll the reader.
    func goToNextFolder() {
        revealFolderKeyboardTarget(
            DiffKeyboardNavigationResolver.nextFolder(
                visibleLines: visibleTreeLines,
                focusedPath: focusedFilePath
            )
        )
    }

    /// Shift+↑ — jump to the previous folder line. Same no-auto-open / no-reader-move.
    func goToPreviousFolder() {
        revealFolderKeyboardTarget(
            DiffKeyboardNavigationResolver.previousFolder(
                visibleLines: visibleTreeLines,
                focusedPath: focusedFilePath
            )
        )
    }

    /// Shift+→ — open the folder under the cursor (or the file's parent). Already-open
    /// and root-level files are silent no-ops.
    func openFocusedFolder() {
        guard let directory = folderPathUnderKeyboardCursor() else { return }
        guard closedDirectories.contains(directory) else { return }
        closedDirectories.remove(directory)
        persistReadingProgress()
    }

    /// Shift+← — close the folder under the cursor (or the file's parent). When closing
    /// hides the current line, the cursor moves onto the folder itself so it stays on
    /// a visible row.
    func closeFocusedFolder() {
        guard let directory = folderPathUnderKeyboardCursor() else { return }
        guard !closedDirectories.contains(directory) else { return }
        closedDirectories.insert(directory)
        if focusedFilePath != directory {
            focusedFilePath = directory
        }
        persistReadingProgress()
    }

    /// Directory key for open/close. Cursor on a folder → that folder. Cursor on a
    /// file → its immediate parent. Nil when there is no cursor or the file is root-level.
    private func folderPathUnderKeyboardCursor() -> String? {
        DiffKeyboardNavigationResolver.folderPathForToggle(
            focusedPath: focusedFilePath,
            parentDirectoryOfFile: { path in
                file(atPath: path)?.directory ?? ""
            }
        )
    }

    /// Folder jumps only move the tree cursor — never the reader, never auto-open.
    private func revealFolderKeyboardTarget(_ navigation: DiffKeyboardNavigation) {
        switch navigation {
        case let .moveTo(path):
            focusTreeLine(path)
        case .stay:
            return
        }
    }

    // MARK: - Sidebar → reader navigation

    func isFocusedInSidebar(_ file: DiffFile) -> Bool {
        focusedFilePath == file.path
    }

    func isFocusedInSidebar(_ directory: DiffTreeDirectory) -> Bool {
        focusedFilePath == directory.path
    }

    /// Sidebar file row click / keyboard file jump. Marks the file current; scrolls the
    /// reader when the file is in `sectionFiles`. Does not expand a collapsed file —
    /// the section header is still the visual target (via pin). `fileScroll: .rapid`
    /// identity-bootstraps during key-repeat; key-up issues `.settled`. Focus updates
    /// immediately either way.
    ///
    /// Does **not** open closed ancestor folders — callers that need that (`n`,
    /// progress restore) call `ensureAncestorDirectoriesOpen` themselves.
    func revealFileInReader(
        _ file: DiffFile,
        fileScroll: DiffReaderFileScrollStyle = .settled
    ) {
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
                scrollStyle: fileScroll
            )
        case .unavailableInReader:
            readerScrollRequest = nil
        }
        persistReadingProgress()
    }

    /// Ends an in-flight scroll sequence without touching sidebar focus.
    func clearReaderScrollRequest() {
        readerScrollRequest = nil
    }

    /// One settled jump for an explicit file path — used when a ←/→ repeat burst ends
    /// so settlement targets the last rapid file, not the folder the cursor may sit on.
    /// Does not move tree focus or advance the cursor.
    func settleReaderScrollOnFile(path: String) {
        if DiffTreeLinePath.isDirectory(path) { return }
        let sectionPaths = Set(sectionFiles.map(\.path))
        guard sectionPaths.contains(path) else { return }
        readerScrollNonce &+= 1
        readerScrollRequest = DiffReaderScrollRequest(
            path: path,
            nonce: readerScrollNonce,
            scrollStyle: .settled
        )
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
        } else {
            collapsedPaths.insert(file.path)
        }
        persistReadingProgress()
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
        persistReadingProgress()
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
        persistReadingProgress()
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
        persistReadingProgress()
    }
}
