import Foundation

extension DiffModel {
    // MARK: - Keyboard navigation

    /// `j` — reveal the next file in reader order.
    func goToNextFile() {
        revealKeyboardTarget(
            DiffKeyboardNavigationResolver.nextFile(
                orderedPaths: sectionFilePaths,
                focusedPath: focusedFilePath
            )
        )
    }

    /// `k` — reveal the previous file in reader order.
    func goToPreviousFile() {
        revealKeyboardTarget(
            DiffKeyboardNavigationResolver.previousFile(
                orderedPaths: sectionFilePaths,
                focusedPath: focusedFilePath
            )
        )
    }

    /// `n` — reveal the next unread file, wrapping from the top when needed.
    func goToNextUnreadFile() {
        let viewed = viewedPaths
        let readHunks = readHunkIDs
        let hunkIDsByPath = Dictionary(
            uniqueKeysWithValues: sectionFiles.map { file in
                (file.path, file.hunks.map(\.id))
            }
        )
        revealKeyboardTarget(
            DiffKeyboardNavigationResolver.nextUnreadFile(
                orderedPaths: sectionFilePaths,
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
        )
    }

    /// `v` — toggle viewed on the file under the cursor.
    func toggleViewedOnFocusedFile() {
        guard let path = focusedFilePath, let file = file(atPath: path) else { return }
        toggleViewed(file)
    }

    // MARK: - Private

    private var sectionFilePaths: [String] {
        sectionFiles.map(\.path)
    }

    private func revealKeyboardTarget(_ navigation: DiffKeyboardNavigation) {
        switch navigation {
        case let .moveTo(path):
            guard let file = file(atPath: path) else { return }
            revealFileInReader(file)
        case .stay:
            return
        }
    }
}
