import Foundation

/// One file in an assembled patch: envelope metadata plus parsed hunks.
nonisolated struct PatchFile: Equatable, Sendable {
    let path: String
    let oldPath: String?
    let change: PatchFileChange
    let hunks: [PatchHunk]
    let isBinary: Bool
    let isSubmodule: Bool
    let additions: Int
    let deletions: Int
    /// Exact unified-section bytes this file was parsed from. Kept so the agent can
    /// receive what git produced without reconstructing a patch that might diverge.
    let rawBody: String?

    init(
        path: String,
        oldPath: String?,
        change: PatchFileChange,
        hunks: [PatchHunk],
        isBinary: Bool,
        isSubmodule: Bool,
        additions: Int,
        deletions: Int,
        rawBody: String? = nil
    ) {
        self.path = path
        self.oldPath = oldPath
        self.change = change
        self.hunks = hunks
        self.isBinary = isBinary
        self.isSubmodule = isSubmodule
        self.additions = additions
        self.deletions = deletions
        self.rawBody = rawBody
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
                isBinary: false,
                isSubmodule: false,
                additions: counts.additions,
                deletions: counts.deletions,
                rawBody: body
            )

        case .binary:
            return PatchFile(
                path: envelope.path,
                oldPath: envelope.oldPath,
                change: envelope.change,
                hunks: [],
                isBinary: true,
                isSubmodule: false,
                additions: 0,
                deletions: 0,
                rawBody: nil
            )

        case .submodule:
            return PatchFile(
                path: envelope.path,
                oldPath: envelope.oldPath,
                change: envelope.change,
                hunks: [],
                isBinary: false,
                isSubmodule: true,
                additions: 0,
                deletions: 0,
                rawBody: nil
            )

        case .noContent:
            return PatchFile(
                path: envelope.path,
                oldPath: envelope.oldPath,
                change: envelope.change,
                hunks: [],
                isBinary: false,
                isSubmodule: false,
                additions: 0,
                deletions: 0,
                rawBody: nil
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
