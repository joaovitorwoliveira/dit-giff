import SwiftUI
import Testing

@testable import DitGiff

@MainActor
struct DiffHunkRenderCacheTests {
    @Test func cacheHitReturnsSameSpansWithoutRecalculating() {
        var producerCalls = 0
        let cache = DiffHunkRenderCache { hunk in
            producerCalls += 1
            return [hunkMarkerSpans(for: hunk)]
        }
        let hunk = cacheTestHunk(id: "h1", lineText: "let a = 1")

        let first = cache.syntaxSpans(for: hunk)
        let second = cache.syntaxSpans(for: hunk)

        #expect(producerCalls == 1)
        #expect(first == second)
        #expect(first[0].contains(SyntaxSpan(start: 0, length: 2, kind: .keyword)))
    }

    @Test func differentHunksDoNotCollide() {
        var producerCalls = 0
        let cache = DiffHunkRenderCache { hunk in
            producerCalls += 1
            return [hunkMarkerSpans(for: hunk)]
        }
        let left = cacheTestHunk(id: "left", lineText: "left")
        let right = cacheTestHunk(id: "right", lineText: "right")

        let leftSpans = cache.syntaxSpans(for: left)
        let rightSpans = cache.syntaxSpans(for: right)

        #expect(producerCalls == 2)
        #expect(leftSpans != rightSpans)
        #expect(cache.entryCount == 2)
    }

    @Test func sizeLimitEvictsOldestEntry() {
        var producerCalls = 0
        let cache = DiffHunkRenderCache(maxEntryCount: 2) { hunk in
            producerCalls += 1
            return [hunkMarkerSpans(for: hunk)]
        }
        let first = cacheTestHunk(id: "h1", lineText: "one")
        let second = cacheTestHunk(id: "h2", lineText: "two")
        let third = cacheTestHunk(id: "h3", lineText: "three")

        _ = cache.syntaxSpans(for: first)
        _ = cache.syntaxSpans(for: second)
        _ = cache.syntaxSpans(for: third)

        #expect(cache.entryCount == 2)
        #expect(producerCalls == 3)

        _ = cache.syntaxSpans(for: first)

        #expect(producerCalls == 4)
        #expect(cache.entryCount == 2)
    }

    @Test func repeatedLookupLexesOnlyOnce() {
        var producerCalls = 0
        let cache = DiffHunkRenderCache { _ in
            producerCalls += 1
            return [[SyntaxSpan(start: 0, length: 1, kind: .keyword)]]
        }
        let hunk = cacheTestHunk(id: "hot", lineText: "func main() {}")

        for _ in 0..<12 {
            _ = cache.syntaxSpans(for: hunk)
            _ = cache.rowIDs(for: hunk)
        }

        #expect(producerCalls == 1)
    }

    @Test func resetClearsMemoizedEntries() {
        var producerCalls = 0
        let cache = DiffHunkRenderCache { _ in
            producerCalls += 1
            return [[SyntaxSpan(start: 0, length: 1, kind: .number)]]
        }
        let hunk = cacheTestHunk(id: "reset-me", lineText: "42")

        _ = cache.syntaxSpans(for: hunk)
        cache.reset()
        _ = cache.syntaxSpans(for: hunk)

        #expect(producerCalls == 2)
        #expect(cache.entryCount == 1)
    }

    @Test func unreadEnvironmentReturnsNilWithoutTrap() {
        let values = EnvironmentValues()
        #expect(values.diffHunkRenderCache == nil)
    }

    @Test func fallbackMatchesCacheForSameHunk() {
        let hunk = cacheTestHunk(id: "fallback", lineText: "let x = 42")
        let cache = DiffHunkRenderCache()

        let cachedSpans = cache.syntaxSpans(for: hunk)
        let cachedRows = cache.rowIDs(for: hunk)
        let directSpans = DiffSyntaxAdapter.syntaxSpans(for: hunk)
        let directRows = DiffLineIdentity.rowIDs(hunkID: hunk.id, lineCount: hunk.lines.count)

        #expect(directSpans == cachedSpans)
        #expect(directRows == cachedRows)
    }

    @Test func rowIDsAreMemoizedWithSyntaxSpans() {
        var producerCalls = 0
        let cache = DiffHunkRenderCache { _ in
            producerCalls += 1
            return [[SyntaxSpan(start: 0, length: 1, kind: .keyword)]]
        }
        let hunk = cacheTestHunk(id: "rows", lineText: "a", extraLines: 2)

        let firstRows = cache.rowIDs(for: hunk)
        let secondRows = cache.rowIDs(for: hunk)

        #expect(producerCalls == 1)
        #expect(firstRows == secondRows)
        #expect(firstRows.map(\.id) == ["rows:0", "rows:1", "rows:2"])
    }
}

private func cacheTestHunk(id: String, lineText: String, extraLines: Int = 0) -> DiffHunk {
    var lines = [
        DiffLine(
            oldNumber: 1,
            newNumber: 1,
            kind: .context,
            segments: [DiffLineSegment(text: lineText)]
        ),
    ]
    if extraLines > 0 {
        for index in 1...extraLines {
            lines.append(
                DiffLine(
                    oldNumber: index + 1,
                    newNumber: index + 1,
                    kind: .context,
                    segments: [DiffLineSegment(text: "line \(index + 1)")]
                )
            )
        }
    }

    return DiffHunk(
        id: id,
        filePath: "\(id).swift",
        header: "@@",
        location: "\(id).swift:1",
        note: nil,
        explanation: nil,
        reply: nil,
        lines: lines
    )
}

private func hunkMarkerSpans(for hunk: DiffHunk) -> [SyntaxSpan] {
    let markerLength = hunk.id.count
    return [SyntaxSpan(start: 0, length: markerLength, kind: .keyword)]
}
