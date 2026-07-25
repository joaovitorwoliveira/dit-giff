import Foundation

/// Named failures while reading one file's patch body. Copy is English and actionable.
nonisolated enum HunkParserError: Error, Equatable, LocalizedError {
    case invalidHeader(String)
    case unexpectedLine(String)
    case lineCountMismatch(
        header: String,
        expectedOld: Int,
        actualOld: Int,
        expectedNew: Int,
        actualNew: Int
    )

    var errorDescription: String? {
        switch self {
        case let .invalidHeader(line):
            "Could not parse hunk header “\(line)”. Expected “@@ -old[,count] +new[,count] @@”."
        case let .unexpectedLine(line):
            "Unexpected line in patch body: “\(line)”. Diff lines must start with a space, “+”, or “-”, be empty context, or be exactly “\\ No newline at end of file”."
        case let .lineCountMismatch(header, expectedOld, actualOld, expectedNew, actualNew):
            "Hunk “\(header)” declared \(expectedOld) old and \(expectedNew) new lines, but the body has \(actualOld) old and \(actualNew) new. The patch is truncated or corrupt."
        }
    }
}

/// Pure parse of one file's patch body — from the first `@@` through the end of
/// that file's section. No git, no process: string in, `[PatchHunk]` out.
nonisolated enum HunkParser {
    /// Marker git emits when a file (or side of a change) has no trailing newline.
    /// Not a diff line — must not become a `PatchLine` or advance numbering.
    static let noNewlineMarker = "\\ No newline at end of file"

    static func parse(_ body: String) throws -> [PatchHunk] {
        let lines = splitPatchLines(body)
        var hunks: [PatchHunk] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let headerInfo = try parseHeader(line)
            index += 1

            var oldLine = headerInfo.oldStart
            var newLine = headerInfo.newStart
            var actualOld = 0
            var actualNew = 0
            var pendingDeletions: [PendingLine] = []
            var pendingAdditions: [PendingLine] = []
            var hunkLines: [PatchLine] = []

            func flushChangeBlock() {
                hunkLines += highlightedLines(
                    deletions: pendingDeletions,
                    additions: pendingAdditions
                )
                pendingDeletions.removeAll(keepingCapacity: true)
                pendingAdditions.removeAll(keepingCapacity: true)
            }

            while index < lines.count {
                let raw = lines[index]
                if raw.hasPrefix("@@") {
                    break
                }
                if raw == noNewlineMarker {
                    index += 1
                    continue
                }
                if raw.hasPrefix("\\") {
                    throw HunkParserError.unexpectedLine(raw)
                }

                if raw.hasPrefix("+") {
                    // A new addition after deletions stays in the change block.
                    // Context or a second deletion-run would have flushed already.
                    let text = String(raw.dropFirst())
                    pendingAdditions.append(
                        PendingLine(oldNumber: nil, newNumber: newLine, kind: .addition, text: text)
                    )
                    newLine += 1
                    actualNew += 1
                    index += 1
                    continue
                }

                if raw.hasPrefix("-") {
                    // A deletion after additions starts a new change block.
                    if !pendingAdditions.isEmpty {
                        flushChangeBlock()
                    }
                    let text = String(raw.dropFirst())
                    pendingDeletions.append(
                        PendingLine(oldNumber: oldLine, newNumber: nil, kind: .deletion, text: text)
                    )
                    oldLine += 1
                    actualOld += 1
                    index += 1
                    continue
                }

                // Context: leading space, or empty (git sometimes omits the space).
                if raw.hasPrefix(" ") || raw.isEmpty {
                    flushChangeBlock()
                    let text = raw.hasPrefix(" ") ? String(raw.dropFirst()) : ""
                    hunkLines.append(
                        PatchLine(
                            oldNumber: oldLine,
                            newNumber: newLine,
                            kind: .context,
                            segments: [PatchLineSegment(text: text)]
                        )
                    )
                    oldLine += 1
                    newLine += 1
                    actualOld += 1
                    actualNew += 1
                    index += 1
                    continue
                }

                throw HunkParserError.unexpectedLine(raw)
            }

            flushChangeBlock()

            if actualOld != headerInfo.oldCount || actualNew != headerInfo.newCount {
                throw HunkParserError.lineCountMismatch(
                    header: headerInfo.header,
                    expectedOld: headerInfo.oldCount,
                    actualOld: actualOld,
                    expectedNew: headerInfo.newCount,
                    actualNew: actualNew
                )
            }

            hunks.append(
                PatchHunk(
                    header: headerInfo.header,
                    oldStart: headerInfo.oldStart,
                    oldCount: headerInfo.oldCount,
                    newStart: headerInfo.newStart,
                    newCount: headerInfo.newCount,
                    lines: hunkLines
                )
            )
        }

        return hunks
    }

    // MARK: - Header

    private struct HeaderInfo: Equatable {
        let header: String
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    private static func parseHeader(_ line: String) throws -> HeaderInfo {
        // @@ -oldStart[,oldCount] +newStart[,newCount] @@[trailing context]
        guard line.hasPrefix("@@ -") else {
            throw HunkParserError.invalidHeader(line)
        }

        var cursor = line.dropFirst(4)

        guard let oldStart = takeInt(from: &cursor) else {
            throw HunkParserError.invalidHeader(line)
        }
        let oldCount: Int
        if cursor.first == "," {
            cursor = cursor.dropFirst()
            guard let count = takeInt(from: &cursor) else {
                throw HunkParserError.invalidHeader(line)
            }
            oldCount = count
        } else {
            oldCount = 1
        }

        guard cursor.hasPrefix(" +") else {
            throw HunkParserError.invalidHeader(line)
        }
        cursor = cursor.dropFirst(2)

        guard let newStart = takeInt(from: &cursor) else {
            throw HunkParserError.invalidHeader(line)
        }
        let newCount: Int
        if cursor.first == "," {
            cursor = cursor.dropFirst()
            guard let count = takeInt(from: &cursor) else {
                throw HunkParserError.invalidHeader(line)
            }
            newCount = count
        } else {
            newCount = 1
        }

        guard cursor.hasPrefix(" @@") else {
            throw HunkParserError.invalidHeader(line)
        }

        return HeaderInfo(
            header: line,
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount
        )
    }

    private static func takeInt(from cursor: inout Substring) -> Int? {
        var digits = Substring()
        while let first = cursor.first, first.isASCII && first.isNumber {
            digits.append(first)
            cursor = cursor.dropFirst()
        }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    // MARK: - Intraline pairing

    private struct PendingLine {
        let oldNumber: Int?
        let newNumber: Int?
        let kind: PatchLineKind
        let text: String
    }

    /// When a deletion block is followed immediately by an addition block of the
    /// same length, pair line-by-line. Otherwise every segment stays plain.
    private static func highlightedLines(
        deletions: [PendingLine],
        additions: [PendingLine]
    ) -> [PatchLine] {
        guard !deletions.isEmpty || !additions.isEmpty else { return [] }

        if deletions.count == additions.count, !deletions.isEmpty {
            var result: [PatchLine] = []
            result.reserveCapacity(deletions.count + additions.count)
            var deletionSegments: [[PatchLineSegment]] = []
            var additionSegments: [[PatchLineSegment]] = []
            deletionSegments.reserveCapacity(deletions.count)
            additionSegments.reserveCapacity(additions.count)

            for index in deletions.indices {
                let highlighted = IntralineHighlighter.highlight(
                    deletion: deletions[index].text,
                    addition: additions[index].text
                )
                deletionSegments.append(highlighted.deletion)
                additionSegments.append(highlighted.addition)
            }

            for (pending, segments) in zip(deletions, deletionSegments) {
                result.append(
                    PatchLine(
                        oldNumber: pending.oldNumber,
                        newNumber: pending.newNumber,
                        kind: pending.kind,
                        segments: segments
                    )
                )
            }
            for (pending, segments) in zip(additions, additionSegments) {
                result.append(
                    PatchLine(
                        oldNumber: pending.oldNumber,
                        newNumber: pending.newNumber,
                        kind: pending.kind,
                        segments: segments
                    )
                )
            }
            return result
        }

        return (deletions + additions).map { pending in
            PatchLine(
                oldNumber: pending.oldNumber,
                newNumber: pending.newNumber,
                kind: pending.kind,
                segments: [PatchLineSegment(text: pending.text)]
            )
        }
    }

    // MARK: - Line splitting

    /// Split on the `"\n"` substring, not on `Character`. In Swift `\r\n` is one
    /// Character, so Character-splitting would keep CRLF glued together; git's
    /// patch separator is the LF byte, and the CR stays as line content — stripping
    /// it would hide a commit that only converts CRLF to LF.
    private static func splitPatchLines(_ body: String) -> [String] {
        if body.isEmpty { return [] }
        var lines = body.components(separatedBy: "\n")
        // `hasSuffix("\n")` is false when the body ends in `\r\n` (one Character),
        // so detect the terminating LF by its UTF-8 byte.
        if body.utf8.last == UInt8(ascii: "\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
