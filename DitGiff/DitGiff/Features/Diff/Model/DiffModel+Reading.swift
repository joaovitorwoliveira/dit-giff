import Foundation

extension DiffModel {
    // MARK: - Read hunks

    /// A viewed file has been read whole, so its hunks count even if none was ticked.
    func isRead(_ hunk: DiffHunk) -> Bool {
        viewedPaths.contains(hunk.filePath) || readHunkIDs.contains(hunk.id)
    }

    /// Unticking a hunk of a file marked viewed contradicts the file: the file stops
    /// being viewed, rather than the tick being ignored. It goes through the same door
    /// as the Viewed button, so the file cannot end up unviewed yet collapsed.
    func toggleRead(_ hunk: DiffHunk) {
        guard isRead(hunk) else {
            readHunkIDs.insert(hunk.id)
            refreshReadProgress()
            persistReadingProgress()
            return
        }
        readHunkIDs.remove(hunk.id)
        guard let file = file(atPath: hunk.filePath) else {
            refreshReadProgress()
            persistReadingProgress()
            return
        }
        setViewed(false, for: file)
    }

    var sectionHunks: [DiffHunk] {
        sectionFiles.flatMap(\.hunks)
    }

    var totalHunkCount: Int { declaredTotalHunkCount }

    var progressText: String {
        "\(readHunkCount) of \(totalHunkCount) hunks read"
    }

    var progressFraction: Double {
        guard totalHunkCount > 0 else { return 0 }
        return min(1, Double(readHunkCount) / Double(totalHunkCount))
    }

    var allRead: Bool {
        readHunkCount >= totalHunkCount
    }

    // MARK: - Selection

    /// The drag gesture works in rows, because that is the granularity it can hit.
    /// Out-of-range rows are clamped rather than dropped: a drag past the last line
    /// still means "to the end".
    func selectLines(inHunkWithID hunkID: String, from: Int, through: Int) {
        guard let hunk = hunk(withID: hunkID), !hunk.lines.isEmpty else {
            selection = nil
            return
        }
        let bounds = 0...(hunk.lines.count - 1)
        let lower = min(from, through).clamped(to: bounds)
        let upper = max(from, through).clamped(to: bounds)
        let rows = lower...upper
        selection = DiffSelection(
            hunkID: hunk.id,
            fileName: fileName(forPath: hunk.filePath),
            rows: rows,
            lineNumbers: rows.compactMap { hunk.lines[$0].displayedNumber }
        )
    }

    func clearSelection() {
        selection = nil
    }
}
