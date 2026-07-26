/// Outcome of a keyboard navigation step. Distinguishes a concrete target from a no-op
/// so callers never treat "nowhere to go" as an ambiguous nil path.
nonisolated enum DiffKeyboardNavigation: Equatable, Sendable {
    case moveTo(path: String)
    case stay
}

/// Whether a file counts as read for "next unread" keyboard navigation.
///
/// A file is read when it is viewed, or when it has hunks and every hunk is read.
/// A zero-hunk file (binary, submodule, no content) is read only when viewed —
/// otherwise `n` would stall on it forever, or treat it as free progress.
nonisolated enum DiffFileReadDecision {
    static func isRead(
        path: String,
        hunkIDs: [String],
        viewedPaths: Set<String>,
        readHunkIDs: Set<String>
    ) -> Bool {
        if viewedPaths.contains(path) { return true }
        if hunkIDs.isEmpty { return false }
        return hunkIDs.allSatisfy { readHunkIDs.contains($0) }
    }
}

/// Pure rules for j / k / n in the reader. The model reveals; this only picks a path.
nonisolated enum DiffKeyboardNavigationResolver {
    /// `j` — next file in reader order. Nil cursor goes to the first. No wrap at the end.
    static func nextFile(
        orderedPaths: [String],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        guard !orderedPaths.isEmpty else { return .stay }
        guard let focusedPath, let index = orderedPaths.firstIndex(of: focusedPath) else {
            return .moveTo(path: orderedPaths[orderedPaths.startIndex])
        }
        let nextIndex = orderedPaths.index(after: index)
        guard nextIndex < orderedPaths.endIndex else { return .stay }
        return .moveTo(path: orderedPaths[nextIndex])
    }

    /// `k` — previous file in reader order. Nil cursor goes to the last. No wrap at the start.
    static func previousFile(
        orderedPaths: [String],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        guard !orderedPaths.isEmpty else { return .stay }
        guard let focusedPath, let index = orderedPaths.firstIndex(of: focusedPath) else {
            return .moveTo(path: orderedPaths[orderedPaths.index(before: orderedPaths.endIndex)])
        }
        guard index > orderedPaths.startIndex else { return .stay }
        return .moveTo(path: orderedPaths[orderedPaths.index(before: index)])
    }

    /// `n` — next unread file after the cursor, wrapping from the top. Stays when every
    /// file is already read.
    static func nextUnreadFile(
        orderedPaths: [String],
        focusedPath: String?,
        isRead: (String) -> Bool
    ) -> DiffKeyboardNavigation {
        guard !orderedPaths.isEmpty else { return .stay }

        let startIndex: Int
        if let focusedPath, let index = orderedPaths.firstIndex(of: focusedPath) {
            startIndex = index + 1
        } else {
            startIndex = 0
        }

        let count = orderedPaths.count
        for offset in 0..<count {
            let index = (startIndex + offset) % count
            let path = orderedPaths[index]
            if !isRead(path) {
                return .moveTo(path: path)
            }
        }
        return .stay
    }
}
