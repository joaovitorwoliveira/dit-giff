import CryptoKit
import Foundation

/// Identifies one reading session: a repository plus the two refs being compared.
/// Refs are canonical (`refs/heads/foo`), never display names.
nonisolated struct ReadingProgressKey: Codable, Equatable, Hashable, Sendable {
    let repositoryPath: String
    let baseRef: String
    let compareRef: String
}

/// Per-file reading marks. Survives a relaunch only while `patchFingerprint` still
/// matches the current patch body — a changed fingerprint means the reader has not
/// seen this version.
nonisolated struct FileReadingProgress: Codable, Equatable, Sendable {
    let path: String
    let patchFingerprint: String
    let isViewed: Bool
    /// Hunks marked read individually. Stored as an array so JSON stays stable.
    let readHunkIDs: [String]
    let isCollapsed: Bool
}

/// Reading state for one key. Folders closed in the tree are not claims about having
/// read anything, so reconciliation keeps them without checking fingerprints.
nonisolated struct SessionReadingProgress: Codable, Equatable, Sendable {
    let files: [FileReadingProgress]
    let closedDirectories: [String]
    let focusedFilePath: String?
}

/// One persisted session plus when it was last written.
nonisolated struct ReadingProgressEntry: Codable, Equatable, Sendable {
    let key: ReadingProgressKey
    let progress: SessionReadingProgress
    let updatedAt: Date
}

/// On-disk envelope. `schemaVersion` lets a future format migrate instead of wiping.
nonisolated struct ReadingProgressDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var entries: [ReadingProgressEntry]
}

/// Named failures. A missing file is not one of these — that is first use.
nonisolated enum ReadingProgressStoreError: Error, Equatable, LocalizedError {
    case corrupted(reason: String)
    case writeFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case let .corrupted(reason):
            "Reading progress file is unreadable. \(reason)"
        case let .writeFailed(reason):
            "Could not save reading progress. \(reason)"
        }
    }
}

// MARK: - Fingerprint

/// Stable hex SHA-256 of the raw patch body. Deterministic across process launches —
/// never `hashValue`, which is seeded per process and would silently break restore.
func readingProgressFingerprint(for patchBody: String) -> String {
    let digest = SHA256.hash(data: Data(patchBody.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Reconciliation

/// Pure: keeps file progress only when the saved fingerprint equals the current one.
/// Prefer losing progress over claiming a read that did not happen on this patch.
func reconcileReadingProgress(
    saved: SessionReadingProgress,
    currentFingerprints: [String: String]
) -> SessionReadingProgress {
    let keptFiles = saved.files.compactMap { file -> FileReadingProgress? in
        guard let current = currentFingerprints[file.path] else {
            return nil
        }
        guard current == file.patchFingerprint else {
            return nil
        }
        return file
    }

    let focused: String?
    if let path = saved.focusedFilePath, currentFingerprints[path] != nil {
        focused = path
    } else {
        focused = nil
    }

    return SessionReadingProgress(
        files: keptFiles,
        closedDirectories: saved.closedDirectories,
        focusedFilePath: focused
    )
}
