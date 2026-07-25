import Foundation

/// One row in the recent-repositories list. Paths are stored as-is; existence on disk
/// is not this type's concern.
nonisolated struct RecentRepository: Codable, Equatable, Sendable {
    /// Absolute path of the work-tree root.
    let rootPath: String
    let displayName: String
    let lastOpenedAt: Date
}

/// On-disk envelope. `schemaVersion` lets a future format migrate instead of wiping.
nonisolated struct RecentRepositoriesDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var repositories: [RecentRepository]
}

/// Named failures. A missing file is not one of these — that is first use.
nonisolated enum RecentRepositoriesStoreError: Error, Equatable, LocalizedError {
    case corrupted(reason: String)
    case writeFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case let .corrupted(reason):
            "Recent repositories file is unreadable. \(reason)"
        case let .writeFailed(reason):
            "Could not save recent repositories. \(reason)"
        }
    }
}
