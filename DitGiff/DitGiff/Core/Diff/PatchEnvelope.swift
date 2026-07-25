import Foundation

/// How one path changed between the two tips of a merge-base diff.
nonisolated enum PatchFileChange: Equatable, Sendable {
    case added
    case deleted
    case modified
    case renamed(from: String)
    case copied(from: String)
}

/// The raw body of one file's patch. Hunk/line parsing happens elsewhere.
nonisolated enum PatchFileBody: Equatable, Sendable {
    /// From the first `@@` line through the end of this file's section.
    case text(String)
    case binary
    case submodule
    /// Headers only — no hunks. Covers mode-only changes and empty new files.
    case noContent
}

/// One file's slice of a `git diff`: status/modes from `--raw -z`, body from the
/// matching unified section. Paths come from raw (NUL-safe); the body is still raw text.
nonisolated struct PatchFileEnvelope: Equatable, Sendable {
    let path: String
    let oldPath: String?
    let change: PatchFileChange
    let body: PatchFileBody
    let oldMode: String?
    let newMode: String?
}

/// Named failures while splitting a patch. Copy is English and actionable.
nonisolated enum PatchEnvelopeError: Error, Equatable, LocalizedError {
    case malformedRawEntry(String)
    case unsupportedRawStatus(String)
    case unexpectedPatchPreamble(String)
    case unparseableDiffGitHeader(String)
    case duplicateRawPath(String)
    case duplicatePatchPath(String)
    /// Raw listed this destination path but the unified patch had no matching section.
    case unmatchedRawPath(String)
    /// Unified patch had this destination path but raw listed no matching entry.
    case unmatchedPatchPath(String)
    /// Destination matched, but `a/` / `b/` paths disagreed with the raw record.
    case pathSideMismatch(destination: String, detail: String)

    var errorDescription: String? {
        switch self {
        case let .malformedRawEntry(entry):
            "Could not parse a `git diff --raw -z` record: “\(entry)”. Re-run the diff; if it persists, the Git output format may have changed."
        case let .unsupportedRawStatus(status):
            "Unsupported `git diff --raw` status “\(status)”. Dit Giff handles added, deleted, modified, renamed, copied, and type-change entries."
        case let .unexpectedPatchPreamble(line):
            "Unified diff had content before the first “diff --git” line: “\(line)”. The patch is truncated or not a plain `git diff`."
        case let .unparseableDiffGitHeader(line):
            "Could not read paths from “\(line)”. Expected “diff --git a/<path> b/<path>” with the forced a/ and b/ prefixes."
        case let .duplicateRawPath(path):
            "Raw diff listed “\(path)” more than once. Refusing to guess which section belongs to which record."
        case let .duplicatePatchPath(path):
            "Unified patch had more than one “diff --git” section for “\(path)”. Refusing to guess which body to keep."
        case let .unmatchedRawPath(path):
            "Raw diff listed “\(path)” but the unified patch has no “diff --git” section for that destination path. The two Git outputs are out of sync — re-run both with the same range and rename options."
        case let .unmatchedPatchPath(path):
            "Unified patch has a section for “\(path)” but `git diff --raw` did not list that destination path. The two Git outputs are out of sync — re-run both with the same range and rename options."
        case let .pathSideMismatch(destination, detail):
            "Raw and unified disagree about “\(destination)”: \(detail)"
        }
    }
}

/// Splits a unified `git diff` into per-file envelopes, using `--raw -z` for metadata.
///
/// Matching key is the **destination path** (compare-side / `b/` path): for renames and
/// copies that is the new name; for everything else it is the only path. Position in
/// either list is ignored — a silent cross-wire of status onto the wrong body is worse
/// than a hard failure.
nonisolated enum PatchEnvelope {
    /// - Parameters:
    ///   - unifiedDiff: Output of `git diff` (unified, no color).
    ///   - rawDiff: Output of `git diff --raw -z` for the same range and rename options.
    static func parse(unifiedDiff: String, rawDiff: String) throws -> [PatchFileEnvelope] {
        let rawEntries = try parseRaw(rawDiff)
        let sections = try splitUnifiedSections(unifiedDiff)

        var sectionsByDestination: [String: (source: String, destination: String, lines: [String])] = [:]
        sectionsByDestination.reserveCapacity(sections.count)
        for section in sections {
            let header = section[0]
            let paths = try parseDiffGitHeader(header)
            if sectionsByDestination[paths.destination] != nil {
                throw PatchEnvelopeError.duplicatePatchPath(paths.destination)
            }
            sectionsByDestination[paths.destination] = (
                source: paths.source,
                destination: paths.destination,
                lines: section
            )
        }

        var rawByDestination: [String: RawEntry] = [:]
        rawByDestination.reserveCapacity(rawEntries.count)
        for entry in rawEntries {
            if rawByDestination[entry.path] != nil {
                throw PatchEnvelopeError.duplicateRawPath(entry.path)
            }
            rawByDestination[entry.path] = entry
        }

        var envelopes: [PatchFileEnvelope] = []
        envelopes.reserveCapacity(rawEntries.count)
        var claimedDestinations = Set<String>()

        for entry in rawEntries {
            guard let section = sectionsByDestination[entry.path] else {
                throw PatchEnvelopeError.unmatchedRawPath(entry.path)
            }
            claimedDestinations.insert(entry.path)

            let expectedSource = entry.oldPath ?? entry.path
            if section.source != expectedSource || section.destination != entry.path {
                throw PatchEnvelopeError.pathSideMismatch(
                    destination: entry.path,
                    detail: "raw has \(entry.oldPath.map { "\($0) → \(entry.path)" } ?? entry.path), unified header has \(section.source) → \(section.destination)."
                )
            }

            envelopes.append(
                PatchFileEnvelope(
                    path: entry.path,
                    oldPath: entry.oldPath,
                    change: entry.change,
                    body: body(for: section.lines, modes: entry),
                    oldMode: displayMode(entry.oldMode),
                    newMode: displayMode(entry.newMode)
                )
            )
        }

        for destination in sectionsByDestination.keys where !claimedDestinations.contains(destination) {
            throw PatchEnvelopeError.unmatchedPatchPath(destination)
        }

        return envelopes
    }

    // MARK: - Raw

    struct RawEntry: Equatable, Sendable {
        let oldMode: String
        let newMode: String
        let change: PatchFileChange
        let path: String
        let oldPath: String?
    }

    static func parseRaw(_ rawDiff: String) throws -> [RawEntry] {
        if rawDiff.isEmpty { return [] }

        var entries: [RawEntry] = []
        var cursor = rawDiff.startIndex

        while cursor < rawDiff.endIndex {
            if rawDiff[cursor] == "\n" {
                cursor = rawDiff.index(after: cursor)
                continue
            }

            guard rawDiff[cursor] == ":" else {
                let remnant = String(rawDiff[cursor...].prefix(80))
                throw PatchEnvelopeError.malformedRawEntry(remnant)
            }

            guard let headerEnd = rawDiff[cursor...].firstIndex(of: "\0") else {
                throw PatchEnvelopeError.malformedRawEntry(String(rawDiff[cursor...].prefix(80)))
            }
            let header = String(rawDiff[cursor..<headerEnd])
            cursor = rawDiff.index(after: headerEnd)

            guard let pathEnd = rawDiff[cursor...].firstIndex(of: "\0") else {
                throw PatchEnvelopeError.malformedRawEntry(header)
            }
            let firstPath = String(rawDiff[cursor..<pathEnd])
            cursor = rawDiff.index(after: pathEnd)

            let parsed = try parseRawHeader(header)
            let oldPath: String?
            let path: String

            switch parsed.status {
            case "R", "C":
                guard let secondEnd = rawDiff[cursor...].firstIndex(of: "\0") else {
                    throw PatchEnvelopeError.malformedRawEntry(header)
                }
                oldPath = firstPath
                path = String(rawDiff[cursor..<secondEnd])
                cursor = rawDiff.index(after: secondEnd)
            default:
                oldPath = nil
                path = firstPath
            }

            let change = try change(status: parsed.status, oldPath: oldPath)
            entries.append(
                RawEntry(
                    oldMode: parsed.oldMode,
                    newMode: parsed.newMode,
                    change: change,
                    path: path,
                    oldPath: oldPath
                )
            )
        }

        return entries
    }

    private struct ParsedRawHeader {
        let oldMode: String
        let newMode: String
        let status: String
    }

    private static func parseRawHeader(_ header: String) throws -> ParsedRawHeader {
        // ":oldmode newmode oldsha newsha STATUS"
        let parts = header.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[0].hasPrefix(":") else {
            throw PatchEnvelopeError.malformedRawEntry(header)
        }
        let oldMode = String(parts[0].dropFirst())
        let newMode = String(parts[1])
        let statusToken = String(parts[4])
        guard let statusLetter = statusToken.first, statusLetter.isLetter else {
            throw PatchEnvelopeError.malformedRawEntry(header)
        }
        return ParsedRawHeader(
            oldMode: oldMode,
            newMode: newMode,
            status: String(statusLetter)
        )
    }

    private static func change(status: String, oldPath: String?) throws -> PatchFileChange {
        switch status {
        case "A":
            return .added
        case "D":
            return .deleted
        case "M", "T":
            return .modified
        case "R":
            guard let oldPath else {
                throw PatchEnvelopeError.malformedRawEntry("rename without source path")
            }
            return .renamed(from: oldPath)
        case "C":
            guard let oldPath else {
                throw PatchEnvelopeError.malformedRawEntry("copy without source path")
            }
            return .copied(from: oldPath)
        default:
            throw PatchEnvelopeError.unsupportedRawStatus(status)
        }
    }

    private static func displayMode(_ mode: String) -> String? {
        mode == "000000" ? nil : mode
    }

    // MARK: - Unified sections

    /// `diff --git a/<source> b/<destination>` with forced prefixes. Destination is the match key.
    static func parseDiffGitHeader(_ line: String) throws -> (source: String, destination: String) {
        let prefix = "diff --git a/"
        guard line.hasPrefix(prefix) else {
            throw PatchEnvelopeError.unparseableDiffGitHeader(line)
        }
        let rest = line.dropFirst(prefix.count)
        guard let separator = rest.range(of: " b/") else {
            throw PatchEnvelopeError.unparseableDiffGitHeader(line)
        }
        let source = String(rest[..<separator.lowerBound])
        let destination = String(rest[separator.upperBound...])
        guard !source.isEmpty, !destination.isEmpty else {
            throw PatchEnvelopeError.unparseableDiffGitHeader(line)
        }
        return (source, destination)
    }

    /// Lines of one `diff --git` section, including the header line.
    static func splitUnifiedSections(_ unifiedDiff: String) throws -> [[String]] {
        if unifiedDiff.isEmpty { return [] }

        var sections: [[String]] = []
        var current: [String] = []
        var inSection = false

        let lines = splitKeepingLineEnds(unifiedDiff)
        for line in lines {
            if line.hasPrefix("diff --git ") {
                if inSection {
                    sections.append(current)
                }
                current = [line]
                inSection = true
            } else if inSection {
                current.append(line)
            } else if line.isEmpty {
                continue
            } else {
                throw PatchEnvelopeError.unexpectedPatchPreamble(line)
            }
        }
        if inSection {
            sections.append(current)
        }
        return sections
    }

    /// Split on U+000A. Must use unicode scalars — in Swift `Character`, `\r\n` is a
    /// single value, so comparing to `"\n"` would skip every CRLF and glue the next
    /// `diff --git` header into the previous file's body (silent cross-wire).
    private static func splitKeepingLineEnds(_ text: String) -> [String] {
        if text.isEmpty { return [] }

        let scalars = text.unicodeScalars
        var lines: [String] = []
        var start = scalars.startIndex
        var i = scalars.startIndex

        while i < scalars.endIndex {
            if scalars[i] == "\n" {
                var line = String(String.UnicodeScalarView(scalars[start..<i]))
                if line.unicodeScalars.last == "\r" {
                    line.removeLast()
                }
                lines.append(line)
                i = scalars.index(after: i)
                start = i
            } else {
                i = scalars.index(after: i)
            }
        }

        if start < scalars.endIndex {
            var line = String(String.UnicodeScalarView(scalars[start..<scalars.endIndex]))
            if line.unicodeScalars.last == "\r" {
                line.removeLast()
            }
            lines.append(line)
        }

        return lines
    }

    private static func body(for section: [String], modes: RawEntry) -> PatchFileBody {
        let rest = section.dropFirst()

        if rest.contains(where: isBinaryMarker) {
            return .binary
        }

        if modes.oldMode == "160000" || modes.newMode == "160000" {
            return .submodule
        }
        if rest.contains(where: {
            $0.hasPrefix("+Subproject commit ")
                || $0.hasPrefix("-Subproject commit ")
                || $0.hasPrefix(" Subproject commit ")
        }) {
            return .submodule
        }

        if let hunkIndex = rest.firstIndex(where: { $0.hasPrefix("@@") }) {
            let bodyLines = rest[hunkIndex...]
            return .text(bodyLines.joined(separator: "\n"))
        }

        return .noContent
    }

    private static func isBinaryMarker(_ line: String) -> Bool {
        line.hasPrefix("Binary files ") && line.hasSuffix(" differ")
    }
}
