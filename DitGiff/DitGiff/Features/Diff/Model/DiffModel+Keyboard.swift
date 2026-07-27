import Foundation

extension DiffModel {
    // MARK: - Keyboard navigation

    /// Visible change-map rows in paint order. Closed folders drop their descendants.
    var visibleTreeLines: [DiffTreeLine] {
        DiffTreeVisibleLines.lines(from: fileTree, isDirectoryOpen: isDirectoryOpen)
    }

    /// `→` — next visible tree line (file or folder). Never opens a closed folder.
    /// `isKeyRepeat` skips the animated multi-pass scroll so a held arrow does not
    /// enqueue dozens of competing jumps.
    func goToNextFile(isKeyRepeat: Bool = false) {
        revealKeyboardTarget(
            DiffKeyboardNavigationResolver.nextLine(
                visibleLines: visibleTreeLines,
                focusedPath: focusedFilePath
            ),
            fileScroll: DiffReaderFileScrollStyle.forKeyRepeat(isKeyRepeat)
        )
    }

    /// `←` — previous visible tree line. Never opens a closed folder.
    func goToPreviousFile(isKeyRepeat: Bool = false) {
        revealKeyboardTarget(
            DiffKeyboardNavigationResolver.previousLine(
                visibleLines: visibleTreeLines,
                focusedPath: focusedFilePath
            ),
            fileScroll: DiffReaderFileScrollStyle.forKeyRepeat(isKeyRepeat)
        )
    }

    /// `n` — next unread file, wrapping from the top. May open closed ancestors so the
    /// unread file is reachable — unlike ←/→, this is an explicit "take me to unread".
    func goToNextUnreadFile() {
        let viewed = viewedPaths
        let readHunks = readHunkIDs
        let hunkIDsByPath = Dictionary(
            uniqueKeysWithValues: sectionFiles.map { file in
                (file.path, file.hunks.map(\.id))
            }
        )
        let navigation = DiffKeyboardNavigationResolver.nextUnreadFile(
            orderedPaths: sectionFiles.map(\.path),
            focusedPath: focusedFilePath,
            isRead: { path in
                DiffFileReadDecision.isRead(
                    path: path,
                    hunkIDs: hunkIDsByPath[path] ?? [],
                    viewedPaths: viewed,
                    readHunkIDs: readHunks
                )
            }
        )
        switch navigation {
        case let .moveTo(path):
            ensureAncestorDirectoriesOpen(forFilePath: path)
            guard let file = file(atPath: path) else { return }
            revealFileInReader(file)
        case .stay:
            return
        }
    }

    /// `v` — toggle viewed on the focused tree line. On a folder: mark/unmark every
    /// descendant and close/reopen the folder to match (viewed → closed; unviewed → open).
    func toggleViewedOnFocusedFile() {
        guard let path = focusedFilePath else { return }
        if DiffTreeLinePath.isDirectory(path) {
            guard let directory = DiffTreeLookup.directory(at: path, in: fileTree) else {
                return
            }
            let markingViewed = viewedState(for: directory).togglesTowardAll
            toggleViewed(in: directory)
            if markingViewed {
                closedDirectories.insert(path)
            } else {
                closedDirectories.remove(path)
            }
            persistReadingProgress()
            return
        }
        guard let file = file(atPath: path) else { return }
        toggleViewed(file)
    }

    // MARK: - Private

    private func revealKeyboardTarget(
        _ navigation: DiffKeyboardNavigation,
        fileScroll: DiffReaderFileScrollStyle = .settled
    ) {
        switch navigation {
        case let .moveTo(path):
            focusTreeLine(path, fileScroll: fileScroll)
        case .stay:
            return
        }
    }

    /// Cursor on a folder: update focus only — the reader stays put so landing on a
    /// folder does not jump the viewport across many files. Cursor on a file: scroll
    /// the reader as before.
    func focusTreeLine(
        _ path: String,
        fileScroll: DiffReaderFileScrollStyle = .settled
    ) {
        if DiffTreeLinePath.isDirectory(path) {
            focusedFilePath = path
            persistReadingProgress()
            return
        }
        guard let file = file(atPath: path) else { return }
        revealFileInReader(file, fileScroll: fileScroll)
    }
}
