import SwiftUI

/// Memoizes per-hunk render data (syntax spans and row ids) for the diff reader.
/// Owned once by `DiffViewer` and injected through the environment so `DiffCodeGrid`
/// can look up by hunk id without re-lexing on every struct recreation.
@MainActor
final class DiffHunkRenderCache {
    /// Enough to cover rapid back-scroll through recently seen hunks without retaining
    /// every hunk in a multi-thousand-hunk MR scrolled end to end.
    static let defaultMaxEntryCount = 64

    typealias SyntaxSpansProducer = (DiffHunk) -> [[SyntaxSpan]]

    private struct Entry {
        var syntaxSpans: [[SyntaxSpan]]
        var rowIDs: [DiffLineIdentity.RowID]
    }

    private let maxEntryCount: Int
    private let syntaxSpansProducer: SyntaxSpansProducer
    private var entries: [String: Entry] = [:]
    /// Most recently used hunk id at the end; evicted from the front.
    private var accessOrder: [String] = []

    init(
        maxEntryCount: Int = defaultMaxEntryCount,
        syntaxSpansProducer: @escaping SyntaxSpansProducer = DiffSyntaxAdapter.syntaxSpans(for:)
    ) {
        self.maxEntryCount = maxEntryCount
        self.syntaxSpansProducer = syntaxSpansProducer
    }

    func reset() {
        entries.removeAll(keepingCapacity: false)
        accessOrder.removeAll(keepingCapacity: false)
    }

    func syntaxSpans(for hunk: DiffHunk) -> [[SyntaxSpan]] {
        entry(for: hunk).syntaxSpans
    }

    func rowIDs(for hunk: DiffHunk) -> [DiffLineIdentity.RowID] {
        entry(for: hunk).rowIDs
    }

    /// Test seam: how many distinct hunks are currently memoized.
    var entryCount: Int { entries.count }

    private func entry(for hunk: DiffHunk) -> Entry {
        if let cached = entries[hunk.id] {
            touch(hunkID: hunk.id)
            return cached
        }

        let syntaxSpans = syntaxSpansProducer(hunk)
        let rowIDs = DiffLineIdentity.rowIDs(hunkID: hunk.id, lineCount: hunk.lines.count)
        let entry = Entry(syntaxSpans: syntaxSpans, rowIDs: rowIDs)
        store(entry, for: hunk.id)
        return entry
    }

    private func store(_ entry: Entry, for hunkID: String) {
        entries[hunkID] = entry
        touch(hunkID: hunkID)
        evictIfNeeded()
    }

    private func touch(hunkID: String) {
        if let index = accessOrder.firstIndex(of: hunkID) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(hunkID)
    }

    private func evictIfNeeded() {
        while accessOrder.count > maxEntryCount {
            let oldest = accessOrder.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}

// MARK: - Environment

// Cache is an optimization (per-hunk memoization). Missing cache degrades performance,
// never crashes the app — SwiftUI may read environment values before injection lands.

private struct DiffHunkRenderCacheKey: EnvironmentKey {
    static let defaultValue: DiffHunkRenderCache? = nil
}

extension EnvironmentValues {
    var diffHunkRenderCache: DiffHunkRenderCache? {
        get { self[DiffHunkRenderCacheKey.self] }
        set { self[DiffHunkRenderCacheKey.self] = newValue }
    }
}
