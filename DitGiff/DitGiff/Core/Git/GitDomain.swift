import Foundation

/// A local repository the app can read. Always the work-tree root — never a subdirectory.
nonisolated struct GitRepository: Equatable, Sendable {
    let rootURL: URL
    /// The last path component of the root, for lists and titles.
    let displayName: String
    let head: GitHEAD
}

/// Where HEAD points right now. Detached is a valid state, not an error.
nonisolated enum GitHEAD: Equatable, Sendable {
    case branch(String)
    case detached

    /// Short label for lists. Detached is named honestly — never blank.
    var listLabel: String {
        switch self {
        case let .branch(name):
            name
        case .detached:
            "detached HEAD"
        }
    }
}

/// A local or remote-tracking branch. Remotes keep the remote name so the UI can show
/// `origin/develop` without re-parsing the ref.
nonisolated struct GitBranch: Equatable, Sendable, Identifiable {
    /// Short name without a remote prefix — `develop`, `feature/foo`.
    let name: String
    /// Canonical ref — `refs/heads/develop` or `refs/remotes/origin/develop`.
    let fullRef: String
    /// `nil` for a local branch; the remote name (`origin`) for a remote-tracking one.
    let remote: String?

    var id: String { fullRef }

    var isRemote: Bool { remote != nil }

    /// What a branch picker shows: `develop` locally, `origin/develop` for remotes.
    var displayName: String {
        if let remote {
            return "\(remote)/\(name)"
        }
        return name
    }
}

/// Named failures with actionable English copy. No catch-all "unknown".
nonisolated enum GitError: Error, Equatable, LocalizedError {
    case pathDoesNotExist(URL)
    case notARepository(URL)
    case repositoryHasNoCommits(URL)
    /// The short display name the user saw in the menu — never a `refs/…` path.
    case branchNotFound(String)
    case gitUnavailable
    case fetchFailed(reason: String)
    /// `base...compare` needs a merge-base; unrelated histories do not have one.
    case noCommonAncestor(base: String, compare: String)
    /// Diff failed for a reason other than a missing merge-base.
    case couldNotCompare(base: String, compare: String)
    /// A recent entry whose path is gone from disk — moved or deleted.
    case repositoryMovedOrDeleted(URL)

    var errorDescription: String? {
        switch self {
        case let .pathDoesNotExist(url):
            "That path does not exist: \(url.path)"
        case let .notARepository(url):
            "“\(url.path)” is not a Git repository. Choose a folder that contains a .git directory (or is inside one)."
        case let .repositoryHasNoCommits(url):
            "“\(url.path)” has no commits yet. Make an initial commit before opening it here."
        case let .branchNotFound(name):
            "Branch “\(name)” was not found in this repository. Fetch remotes or pick another branch."
        case .gitUnavailable:
            "Git is not available on this Mac. Install Git and make sure `git` is on your PATH."
        case let .fetchFailed(reason):
            "Could not fetch from the remote. \(Self.sanitizedGitReason(reason))"
        case let .noCommonAncestor(base, compare):
            "“\(base)” and “\(compare)” have no common ancestor, so there is no merge-base diff to show. Pick a related pair of branches."
        case let .couldNotCompare(base, compare):
            "Could not compare “\(compare)” against “\(base)”. Fetch remotes, or pick another pair of branches."
        case let .repositoryMovedOrDeleted(url):
            "That repository is no longer at “\(url.path)”. It may have been moved or deleted. You can remove it from the recent list."
        }
    }

    /// Strip ref paths from git stderr so they never surface as UI copy.
    private static func sanitizedGitReason(_ reason: String) -> String {
        reason
            .replacingOccurrences(of: #"refs/heads/[^\s]+"#, with: "a local branch", options: .regularExpression)
            .replacingOccurrences(of: #"refs/remotes/[^\s]+"#, with: "a remote branch", options: .regularExpression)
    }
}

/// Pure guess for which base branch to pre-select. The user can change it freely.
nonisolated enum GitBaseSelection {
    /// Preferred local/remote tip names when `origin/HEAD` is missing.
    static let fallbackNames = ["main", "develop", "master"]

    /// - Parameters:
    ///   - branches: Local and remote-tracking branches (already filtered; no `origin/HEAD`).
    ///   - originHEADRef: Full ref from `refs/remotes/origin/HEAD`, e.g. `refs/remotes/origin/main`.
    ///   - currentBranchName: Short name of the checked-out local branch, if any.
    static func probableBase(
        among branches: [GitBranch],
        originHEADRef: String?,
        currentBranchName: String?
    ) -> GitBranch? {
        if let originHEADRef,
           let fromOrigin = branches.first(where: { $0.fullRef == originHEADRef })
        {
            return fromOrigin
        }

        for name in fallbackNames {
            if let match = branches.first(where: { $0.name == name && $0.remote == nil }) {
                return match
            }
            if let match = branches.first(where: { $0.name == name }) {
                return match
            }
        }

        if let currentBranchName,
           let current = branches.first(where: { $0.name == currentBranchName && $0.remote == nil })
        {
            return current
        }

        return nil
    }
}
