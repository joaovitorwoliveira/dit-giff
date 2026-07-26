import Foundation

/// Kind of patch body after envelope classification. Preserves the distinction
/// between binary, submodule, no-content, and text — never inferred from empty hunks.
nonisolated enum PatchFileKind: Equatable, Sendable {
    case text
    case binary
    case submodule(oldSHA: String?, newSHA: String?)
    case noContent
}

/// One file in an assembled patch: envelope metadata plus parsed hunks.
nonisolated struct PatchFile: Equatable, Sendable {
    let path: String
    let oldPath: String?
    let change: PatchFileChange
    let hunks: [PatchHunk]
    let kind: PatchFileKind
    let additions: Int
    let deletions: Int
    /// Exact unified-section bytes this file was parsed from. Kept so the agent can
    /// receive what git produced without reconstructing a patch that might diverge.
    /// Text only — non-text files leave this nil so Explain stays off.
    let rawBody: String?
    /// Raw header git printed for this file. Non-text reading fingerprints hash this
    /// so blob `index` lines invalidate progress when content changes.
    let rawHeader: String

    var isBinary: Bool {
        if case .binary = kind { return true }
        return false
    }

    var isSubmodule: Bool {
        if case .submodule = kind { return true }
        return false
    }

    init(
        path: String,
        oldPath: String?,
        change: PatchFileChange,
        hunks: [PatchHunk],
        kind: PatchFileKind,
        additions: Int,
        deletions: Int,
        rawBody: String? = nil,
        rawHeader: String = ""
    ) {
        self.path = path
        self.oldPath = oldPath
        self.change = change
        self.hunks = hunks
        self.kind = kind
        self.additions = additions
        self.deletions = deletions
        self.rawBody = rawBody
        self.rawHeader = rawHeader
    }

    /// Convenience for call sites that still spell the old binary/submodule flags.
    init(
        path: String,
        oldPath: String?,
        change: PatchFileChange,
        hunks: [PatchHunk],
        isBinary: Bool,
        isSubmodule: Bool,
        additions: Int,
        deletions: Int,
        rawBody: String? = nil,
        rawHeader: String = ""
    ) {
        let kind: PatchFileKind
        if isBinary {
            kind = .binary
        } else if isSubmodule {
            kind = .submodule(oldSHA: nil, newSHA: nil)
        } else if hunks.isEmpty {
            // Ambiguous: empty hunks with neither flag used to mean no-content.
            kind = .noContent
        } else {
            kind = .text
        }
        self.init(
            path: path,
            oldPath: oldPath,
            change: change,
            hunks: hunks,
            kind: kind,
            additions: additions,
            deletions: deletions,
            rawBody: rawBody,
            rawHeader: rawHeader
        )
    }
}

/// A complete merge-base diff: every changed file with hunks ready for the reader.
nonisolated struct Patch: Equatable, Sendable {
    let files: [PatchFile]

    /// Join envelopes with `HunkParser`. Text bodies are parsed; binary, submodule,
    /// and no-content files keep empty hunks and zero counts.
    static func assemble(from envelopes: [PatchFileEnvelope]) throws -> Patch {
        var files: [PatchFile] = []
        files.reserveCapacity(envelopes.count)

        for envelope in envelopes {
            files.append(try assembleFile(envelope))
        }

        return Patch(files: files)
    }

    private static func assembleFile(_ envelope: PatchFileEnvelope) throws -> PatchFile {
        switch envelope.body {
        case let .text(body):
            let hunks: [PatchHunk]
            do {
                hunks = try HunkParser.parse(body)
            } catch let error as HunkParserError {
                throw PatchError.hunkParseFailed(path: envelope.path, underlying: error)
            }
            let counts = countLineChanges(in: hunks)
            return PatchFile(
                path: envelope.path,
                oldPath: envelope.oldPath,
                change: envelope.change,
                hunks: hunks,
                kind: .text,
                additions: counts.additions,
                deletions: counts.deletions,
                rawBody: body,
                rawHeader: envelope.rawHeader
            )

        case .binary:
            return PatchFile(
                path: envelope.path,
                oldPath: envelope.oldPath,
                change: envelope.change,
                hunks: [],
                kind: .binary,
                additions: 0,
                deletions: 0,
                rawBody: nil,
                rawHeader: envelope.rawHeader
            )

        case let .submodule(oldSHA, newSHA):
            return PatchFile(
                path: envelope.path,
                oldPath: envelope.oldPath,
                change: envelope.change,
                hunks: [],
                kind: .submodule(oldSHA: oldSHA, newSHA: newSHA),
                additions: 0,
                deletions: 0,
                rawBody: nil,
                rawHeader: envelope.rawHeader
            )

        case .noContent:
            return PatchFile(
                path: envelope.path,
                oldPath: envelope.oldPath,
                change: envelope.change,
                hunks: [],
                kind: .noContent,
                additions: 0,
                deletions: 0,
                rawBody: nil,
                rawHeader: envelope.rawHeader
            )
        }
    }

    private static func countLineChanges(in hunks: [PatchHunk]) -> (additions: Int, deletions: Int) {
        var additions = 0
        var deletions = 0
        for hunk in hunks {
            for line in hunk.lines {
                switch line.kind {
                case .addition:
                    additions += 1
                case .deletion:
                    deletions += 1
                case .context:
                    break
                }
            }
        }
        return (additions, deletions)
    }
}

/// Failures while turning envelopes into a `Patch`. Always names the file when possible.
nonisolated enum PatchError: Error, Equatable, LocalizedError {
    case hunkParseFailed(path: String, underlying: HunkParserError)

    var errorDescription: String? {
        switch self {
        case let .hunkParseFailed(path, underlying):
            let detail = underlying.errorDescription ?? String(describing: underlying)
            return "Could not parse hunks in “\(path)”. \(detail)"
        }
    }
}
