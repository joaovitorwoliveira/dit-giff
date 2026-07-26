/// Turns a git-faithful `Patch` into the `DiffFile` / `DiffHunk` values the review
/// screen already draws. No I/O — structure in, structure out.

nonisolated enum PatchAdapter {
    /// One `DiffFile` per `PatchFile`, in the same order. Body kind is propagated;
    /// binary, submodule, and no-content files keep an empty hunk list.
    static func toDiffFiles(_ patch: Patch) -> [DiffFile] {
        patch.files.map(adaptFile)
    }

    // MARK: - File

    private static func adaptFile(_ file: PatchFile) -> DiffFile {
        let status = mapStatus(file.change)
        let isDeletedFile = file.change == .deleted
        let hunks = file.hunks.enumerated().map { index, hunk in
            adaptHunk(
                hunk,
                index: index,
                filePath: file.path,
                isDeletedFile: isDeletedFile
            )
        }
        return DiffFile(
            path: file.path,
            status: status,
            additions: file.additions,
            deletions: file.deletions,
            hunks: hunks,
            body: mapBody(file.kind)
        )
    }

    private static func mapBody(_ kind: PatchFileKind) -> DiffFileBodyKind {
        switch kind {
        case .text:
            .text
        case .binary:
            .binary
        case let .submodule(oldSHA, newSHA):
            .submodule(oldSHA: oldSHA, newSHA: newSHA)
        case .noContent:
            .noContent
        }
    }

    /// Copy has no `DiffFileStatus` case. The destination path is new content while
    /// the source still exists, so `added` is the honest fit — `renamed` would imply
    /// the old path disappeared.
    private static func mapStatus(_ change: PatchFileChange) -> DiffFileStatus {
        switch change {
        case .added, .copied:
            .added
        case .deleted:
            .deleted
        case .modified:
            .modified
        case .renamed:
            .renamed
        }
    }

    // MARK: - Hunk

    private static func adaptHunk(
        _ hunk: PatchHunk,
        index: Int,
        filePath: String,
        isDeletedFile: Bool
    ) -> DiffHunk {
        DiffHunk(
            id: hunkID(filePath: filePath, index: index),
            filePath: filePath,
            header: hunk.header,
            location: location(filePath: filePath, hunk: hunk, isDeletedFile: isDeletedFile),
            note: nil,
            explanation: nil,
            reply: nil,
            lines: hunk.lines.map(adaptLine)
        )
    }

    /// Stable across reopen of the same patch (git hunk order is deterministic) and
    /// unique within a diff: path scopes the index so two files with a hunk at the
    /// same line number cannot collide.
    static func hunkID(filePath: String, index: Int) -> String {
        "\(filePath)#\(index)"
    }

    /// Chip text: file name, colon, line. Prefer the new-side start; deleted files
    /// (and hunks with no new side) fall back to the old-side start.
    private static func location(
        filePath: String,
        hunk: PatchHunk,
        isDeletedFile: Bool
    ) -> String {
        let name = fileName(from: filePath)
        let line: Int
        if isDeletedFile || (hunk.newCount == 0 && hunk.newStart == 0) {
            line = hunk.oldStart
        } else {
            line = hunk.newStart
        }
        return "\(name):\(line)"
    }

    private static func fileName(from path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    // MARK: - Line

    private static func adaptLine(_ line: PatchLine) -> DiffLine {
        DiffLine(
            oldNumber: line.oldNumber,
            newNumber: line.newNumber,
            kind: mapKind(line.kind),
            segments: line.segments.map {
                DiffLineSegment(text: $0.text, isHighlighted: $0.isHighlighted)
            }
        )
    }

    private static func mapKind(_ kind: PatchLineKind) -> DiffLineKind {
        switch kind {
        case .context: .context
        case .addition: .addition
        case .deletion: .deletion
        }
    }
}
