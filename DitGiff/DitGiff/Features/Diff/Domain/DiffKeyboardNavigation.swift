/// Outcome of a keyboard navigation step. Distinguishes a concrete target from a no-op
/// so callers never treat "nowhere to go" as an ambiguous nil path.
nonisolated enum DiffKeyboardNavigation: Equatable, Sendable {
    case moveTo(path: String)
    case stay
}

/// One painted row in the change-map tree: a folder or a file. The keyboard cursor
/// sits on a line, not only on files.
nonisolated enum DiffTreeLine: Equatable, Sendable {
    case directory(path: String)
    case file(path: String)

    var path: String {
        switch self {
        case let .directory(path), let .file(path):
            return path
        }
    }

    var isDirectory: Bool {
        switch self {
        case .directory: true
        case .file: false
        }
    }
}

/// Directory paths in this tree always end with `/` (see `DiffFile.directory`).
nonisolated enum DiffTreeLinePath {
    static func isDirectory(_ path: String) -> Bool {
        path.hasSuffix("/")
    }
}

/// Visible sidebar rows in paint order. Descendants of a closed folder are omitted —
/// closing a folder means "done with this"; ←/→ respect that and skip the hidden rows.
nonisolated enum DiffTreeVisibleLines {
    static func lines(
        from nodes: [DiffTreeNode],
        isDirectoryOpen: (String) -> Bool
    ) -> [DiffTreeLine] {
        nodes.flatMap { lineAndDescendants(of: $0, isDirectoryOpen: isDirectoryOpen) }
    }

    private static func lineAndDescendants(
        of node: DiffTreeNode,
        isDirectoryOpen: (String) -> Bool
    ) -> [DiffTreeLine] {
        switch node {
        case let .directory(directory):
            var result: [DiffTreeLine] = [.directory(path: directory.path)]
            guard isDirectoryOpen(directory.path) else { return result }
            result += directory.children.flatMap {
                lineAndDescendants(of: $0, isDirectoryOpen: isDirectoryOpen)
            }
            return result
        case let .file(file, _):
            return [.file(path: file.path)]
        }
    }
}

/// Lookup helpers over a built tree. Kept pure so keyboard / viewed actions can resolve
/// a directory path without walking from the model.
nonisolated enum DiffTreeLookup {
    static func directory(
        at path: String,
        in nodes: [DiffTreeNode]
    ) -> DiffTreeDirectory? {
        for node in nodes {
            switch node {
            case let .directory(nodeDirectory):
                if nodeDirectory.path == path { return nodeDirectory }
                if let nested = directory(at: path, in: nodeDirectory.children) {
                    return nested
                }
            case .file:
                continue
            }
        }
        return nil
    }
}

/// Reader column order. Must match the sidebar tree's depth-first paint order
/// (directories before loose files at each level), not raw patch order.
///
/// Collapsed folders do **not** remove files from this list — the reader still shows
/// every section file. Visible ←/→ navigation is a separate sequence
/// (`DiffTreeVisibleLines`) that does skip closed folders.
nonisolated enum DiffReaderDisplayOrder {
    static func sectionFiles(from files: [DiffFile]) -> [DiffFile] {
        filesInTreeOrder(from: DiffTree.build(files: files)).filter(\.belongsInReader)
    }

    static func filesInTreeOrder(from nodes: [DiffTreeNode]) -> [DiffFile] {
        nodes.flatMap { node -> [DiffFile] in
            switch node {
            case let .directory(directory):
                return filesInTreeOrder(from: directory.children)
            case let .file(file, _):
                return [file]
            }
        }
    }
}

/// How the reader should jump to a file's scroll anchor. Key-repeat bursts use `.rapid`
/// so each new target replaces the previous jump instead of stacking animations.
nonisolated enum DiffReaderFileScrollStyle: Equatable, Sendable {
    /// One animated pass plus corrective retries after layout settles (click / single key).
    case settled
    /// Single non-animated snap; no retry chain (held ←/→).
    case rapid

    static func forKeyRepeat(_ isKeyRepeat: Bool) -> DiffReaderFileScrollStyle {
        isKeyRepeat ? .rapid : .settled
    }

    /// Maps onto `DiffReaderScrollRetry` attempt indexes without re-encoding that policy.
    var initialAttempt: Int {
        switch self {
        case .settled:
            return DiffReaderScrollRetry.animatedAttempt
        case .rapid:
            return DiffReaderScrollRetry.finalAttempt
        }
    }
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

/// Pure rules for ←/→ / Shift+↑↓ / `n` over visible tree lines. The model reveals;
/// this only picks a path.
nonisolated enum DiffKeyboardNavigationResolver {
    /// `→` — next visible tree line. Nil cursor goes to the first. No wrap at the end.
    static func nextLine(
        visibleLines: [DiffTreeLine],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        step(visibleLines: visibleLines, focusedPath: focusedPath, direction: .forward)
    }

    /// `←` — previous visible tree line. Nil cursor goes to the last. No wrap at the start.
    static func previousLine(
        visibleLines: [DiffTreeLine],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        step(visibleLines: visibleLines, focusedPath: focusedPath, direction: .backward)
    }

    /// Kept as aliases so call sites that still say "file" mean the same line step —
    /// the cursor is a tree line, which may be a folder.
    static func nextFile(
        orderedPaths: [String],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        nextLine(
            visibleLines: orderedPaths.map { path in
                DiffTreeLinePath.isDirectory(path) ? .directory(path: path) : .file(path: path)
            },
            focusedPath: focusedPath
        )
    }

    static func previousFile(
        orderedPaths: [String],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        previousLine(
            visibleLines: orderedPaths.map { path in
                DiffTreeLinePath.isDirectory(path) ? .directory(path: path) : .file(path: path)
            },
            focusedPath: focusedPath
        )
    }

    /// `n` — next unread **file** after the cursor, wrapping from the top. Stays when
    /// every file is already read. `orderedPaths` is the full reader/file list (not
    /// visibility-filtered): `n` may open a collapsed folder to reach an unread file.
    ///
    /// When the cursor sits on a directory, search starts after that folder's
    /// descendant files.
    static func nextUnreadFile(
        orderedPaths: [String],
        focusedPath: String?,
        isRead: (String) -> Bool
    ) -> DiffKeyboardNavigation {
        guard !orderedPaths.isEmpty else { return .stay }

        let startIndex = unreadSearchStartIndex(
            orderedPaths: orderedPaths,
            focusedPath: focusedPath
        )

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

    /// Shift+↓ — next **directory** line after the cursor. Lands on the folder path,
    /// never on its first file.
    static func nextFolder(
        visibleLines: [DiffTreeLine],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        folderStep(visibleLines: visibleLines, focusedPath: focusedPath, direction: .forward)
    }

    /// Shift+↑ — previous **directory** line. Lands on the folder path.
    static func previousFolder(
        visibleLines: [DiffTreeLine],
        focusedPath: String?
    ) -> DiffKeyboardNavigation {
        folderStep(visibleLines: visibleLines, focusedPath: focusedPath, direction: .backward)
    }

    /// Folder the open/close chords should act on. Cursor on a directory → that
    /// directory. Cursor on a file → its immediate parent. Root-level file → nil.
    static func folderPathForToggle(
        focusedPath: String?,
        parentDirectoryOfFile: (String) -> String
    ) -> String? {
        guard let focusedPath else { return nil }
        if DiffTreeLinePath.isDirectory(focusedPath) {
            return focusedPath
        }
        let parent = parentDirectoryOfFile(focusedPath)
        return parent.isEmpty ? nil : parent
    }

    // MARK: - Private

    private enum StepDirection {
        case forward
        case backward
    }

    private static func step(
        visibleLines: [DiffTreeLine],
        focusedPath: String?,
        direction: StepDirection
    ) -> DiffKeyboardNavigation {
        guard !visibleLines.isEmpty else { return .stay }
        let paths = visibleLines.map(\.path)

        guard let focusedPath, let index = paths.firstIndex(of: focusedPath) else {
            switch direction {
            case .forward:
                return .moveTo(path: paths[paths.startIndex])
            case .backward:
                return .moveTo(path: paths[paths.index(before: paths.endIndex)])
            }
        }

        switch direction {
        case .forward:
            let nextIndex = paths.index(after: index)
            guard nextIndex < paths.endIndex else { return .stay }
            return .moveTo(path: paths[nextIndex])
        case .backward:
            guard index > paths.startIndex else { return .stay }
            return .moveTo(path: paths[paths.index(before: index)])
        }
    }

    private static func folderStep(
        visibleLines: [DiffTreeLine],
        focusedPath: String?,
        direction: StepDirection
    ) -> DiffKeyboardNavigation {
        let directories = visibleLines.filter(\.isDirectory)
        guard !directories.isEmpty else { return .stay }

        guard let focusedPath else {
            switch direction {
            case .forward:
                return .moveTo(path: directories[directories.startIndex].path)
            case .backward:
                return .moveTo(
                    path: directories[directories.index(before: directories.endIndex)].path
                )
            }
        }

        let currentFolder = folderContext(
            focusedPath: focusedPath,
            directoryLines: directories
        )
        let anchorIndex = visibleLines.firstIndex(where: { $0.path == currentFolder })
            ?? visibleLines.firstIndex(where: { $0.path == focusedPath })

        switch direction {
        case .forward:
            let start = anchorIndex.map { visibleLines.index(after: $0) }
                ?? visibleLines.startIndex
            guard start < visibleLines.endIndex else { return .stay }
            for line in visibleLines[start...] where line.isDirectory {
                // Skip nested folders still under the current folder.
                if let currentFolder, line.path.hasPrefix(currentFolder) {
                    continue
                }
                return .moveTo(path: line.path)
            }
            return .stay
        case .backward:
            guard let anchorIndex, anchorIndex > visibleLines.startIndex else {
                if anchorIndex == nil {
                    return .moveTo(
                        path: directories[directories.index(before: directories.endIndex)].path
                    )
                }
                return .stay
            }
            let before = visibleLines.index(before: anchorIndex)
            for line in visibleLines[...before].reversed() where line.isDirectory {
                // Skip ancestors of the current folder (parent rows above it).
                if let currentFolder,
                   currentFolder.hasPrefix(line.path),
                   currentFolder != line.path
                {
                    continue
                }
                return .moveTo(path: line.path)
            }
            return .stay
        }
    }

    /// Folder the cursor is "in": the directory line itself, or the deepest open
    /// directory prefix of a file. Used so Shift+↑/↓ jump between folder groups,
    /// not onto the parent row of the file under the cursor.
    private static func folderContext(
        focusedPath: String,
        directoryLines: [DiffTreeLine]
    ) -> String? {
        if DiffTreeLinePath.isDirectory(focusedPath) {
            return focusedPath
        }
        return directoryLines.last { focusedPath.hasPrefix($0.path) }?.path
    }

    private static func unreadSearchStartIndex(
        orderedPaths: [String],
        focusedPath: String?
    ) -> Int {
        guard let focusedPath else { return 0 }
        if DiffTreeLinePath.isDirectory(focusedPath) {
            if let lastDescendant = orderedPaths.lastIndex(where: { $0.hasPrefix(focusedPath) }) {
                return lastDescendant + 1
            }
            return 0
        }
        if let index = orderedPaths.firstIndex(of: focusedPath) {
            return index + 1
        }
        return 0
    }
}
