import Foundation

/// Slices per-hunk unified diff text from a file body as git emitted it.
nonisolated enum DiffHunkPatch {
    /// One entry per hunk in `patch`, keyed by the same ids `PatchAdapter` assigns.
    static func bodies(from patch: Patch) -> [String: String] {
        var result: [String: String] = [:]
        for file in patch.files {
            guard let rawBody = file.rawBody else { continue }
            for index in file.hunks.indices {
                let id = PatchAdapter.hunkID(filePath: file.path, index: index)
                guard let body = slice(rawBody: rawBody, hunkIndex: index) else { continue }
                result[id] = body
            }
        }
        return result
    }

    /// How many hunk sections `slice` can return — must match `HunkParser` on the same body.
    static func hunkSliceCount(in rawBody: String) -> Int {
        let lines = splitPatchLines(rawBody)
        guard let first = lines.first, isHunkBoundaryLine(first) else { return 0 }
        var count = 1
        for index in 1..<lines.count where isHunkBoundaryLine(lines[index]) {
            count += 1
        }
        return count
    }

    /// Returns the Nth hunk section (0-based) from a file's unified body.
    static func slice(rawBody: String, hunkIndex: Int) -> String? {
        let lines = splitPatchLines(rawBody)
        var hunkStarts: [Int] = []
        hunkStarts.reserveCapacity(4)
        for (index, line) in lines.enumerated() where isHunkBoundaryLine(line) {
            hunkStarts.append(index)
        }
        guard hunkStarts.indices.contains(hunkIndex) else { return nil }
        let start = hunkStarts[hunkIndex]
        let end = hunkIndex + 1 < hunkStarts.count ? hunkStarts[hunkIndex + 1] : lines.count
        guard start < end else { return nil }
        return lines[start..<end].joined(separator: "\n")
    }

    /// Same rule `HunkParser` uses between hunks: bare `@@`, never `+@@` / ` @@` content.
    private static func isHunkBoundaryLine(_ line: String) -> Bool {
        line.hasPrefix("@@")
    }

    private static func splitPatchLines(_ body: String) -> [String] {
        if body.isEmpty { return [] }
        var lines = body.components(separatedBy: "\n")
        if body.utf8.last == UInt8(ascii: "\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
