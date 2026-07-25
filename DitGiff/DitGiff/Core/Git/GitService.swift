import Foundation

/// Read-only Git operations behind the existing `CommandRunner` seam.
/// No protocol on top — the seam is the runner; tests stub realistic `git` output.
nonisolated struct GitService: Sendable {
    private let runner: any CommandRunner

    init(runner: any CommandRunner) {
        self.runner = runner
    }

    // MARK: - Availability

    func isGitAvailable() async -> Bool {
        do {
            let output = try await runGit(arguments: ["--version"])
            return output.didSucceed
        } catch is GitError {
            return false
        } catch {
            return false
        }
    }

    // MARK: - Open

    /// Validates `url` (or a subdirectory of a repo) and returns the work-tree root.
    func openRepository(at url: URL) async throws -> GitRepository {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GitError.pathDoesNotExist(url)
        }

        let toplevel = try await runGit(
            arguments: ["rev-parse", "--show-toplevel"],
            workingDirectory: url
        )
        guard toplevel.didSucceed else {
            throw GitError.notARepository(url)
        }

        let rootPath = toplevel.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rootPath.isEmpty else {
            throw GitError.notARepository(url)
        }
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let head = try await currentHEAD(at: rootURL)

        return GitRepository(
            rootURL: rootURL,
            displayName: rootURL.lastPathComponent,
            head: head
        )
    }

    /// Where HEAD points in an already-known work tree. Used for live labels on
    /// the recent list — never persisted; always read from disk.
    func currentHEAD(at rootURL: URL) async throws -> GitHEAD {
        let headProbe = try await runGit(
            arguments: ["rev-parse", "--verify", "--quiet", "HEAD"],
            workingDirectory: rootURL
        )
        guard headProbe.didSucceed else {
            throw GitError.repositoryHasNoCommits(rootURL)
        }

        let symbolic = try await runGit(
            arguments: ["symbolic-ref", "--quiet", "--short", "HEAD"],
            workingDirectory: rootURL
        )
        if symbolic.didSucceed {
            let name = symbolic.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? .detached : .branch(name)
        }
        return .detached
    }

    // MARK: - Branches

    /// Local heads and remote-tracking branches in one list. `refs/remotes/*/HEAD` is omitted.
    ///
    /// `for-each-ref` has no `-z` even on recent Git; `%(refname)%00` is the stable
    /// NUL-terminated form (records may still carry a trailing newline after the NUL).
    func listBranches(in repository: GitRepository) async throws -> [GitBranch] {
        let output = try await runGit(
            arguments: [
                "for-each-ref",
                "--format=%(refname)%00",
                "refs/heads",
                "refs/remotes",
            ],
            workingDirectory: repository.rootURL
        )
        guard output.didSucceed else {
            throw GitError.notARepository(repository.rootURL)
        }

        return Self.parseBranches(fromNULSeparated: output.standardOutput)
    }

    /// Full ref that `refs/remotes/origin/HEAD` points at, or `nil` when absent.
    func originHEADRef(in repository: GitRepository) async throws -> String? {
        let output = try await runGit(
            arguments: ["symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
            workingDirectory: repository.rootURL
        )
        guard output.didSucceed else { return nil }
        let ref = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return ref.isEmpty ? nil : ref
    }

    /// Convenience: list branches, resolve `origin/HEAD`, return the pre-selected base.
    func probableBase(in repository: GitRepository) async throws -> GitBranch? {
        let branches = try await listBranches(in: repository)
        let originHEAD = try await originHEADRef(in: repository)
        let currentName: String?
        if case let .branch(name) = repository.head {
            currentName = name
        } else {
            currentName = nil
        }
        return GitBaseSelection.probableBase(
            among: branches,
            originHEADRef: originHEAD,
            currentBranchName: currentName
        )
    }

    // MARK: - Diff count

    /// Files changed on `compare` since it diverged from `base` (`base...compare`).
    func changedFileCount(
        in repository: GitRepository,
        base: GitBranch,
        compare: GitBranch
    ) async throws -> Int {
        try await ensureRefExists(base, in: repository)
        try await ensureRefExists(compare, in: repository)

        let range = "\(base.fullRef)...\(compare.fullRef)"
        let output = try await runGit(
            arguments: ["diff", "--name-only", "-z", range],
            workingDirectory: repository.rootURL
        )

        if output.didSucceed {
            return Self.countNULSeparatedPaths(output.standardOutput)
        }

        let stderr = output.standardError
        if stderr.localizedCaseInsensitiveContains("no merge base") {
            throw GitError.noCommonAncestor(base: base.displayName, compare: compare.displayName)
        }

        throw GitError.couldNotCompare(base: base.displayName, compare: compare.displayName)
    }

    // MARK: - Fetch

    /// Manual refresh of remotes. Never called automatically.
    func fetch(in repository: GitRepository) async throws {
        let output = try await runGit(
            arguments: ["fetch", "--all", "--prune"],
            workingDirectory: repository.rootURL,
            environment: Self.fetchEnvironment
        )
        guard output.didSucceed else {
            let reason = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                throw GitError.fetchFailed(reason: "git fetch exited with code \(output.exitCode).")
            }
            throw GitError.fetchFailed(reason: reason)
        }
    }

    // MARK: - Parsing (testable)

    static func parseBranches(fromNULSeparated output: String) -> [GitBranch] {
        output.split(separator: "\0", omittingEmptySubsequences: true).compactMap { raw in
            let ref = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ref.isEmpty else { return nil }
            return branch(fromFullRef: ref)
        }
    }

    static func countNULSeparatedPaths(_ output: String) -> Int {
        output.split(separator: "\0", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
            .count
    }

    static func branch(fromFullRef fullRef: String) -> GitBranch? {
        if fullRef.hasPrefix("refs/heads/") {
            let name = String(fullRef.dropFirst("refs/heads/".count))
            guard !name.isEmpty else { return nil }
            return GitBranch(name: name, fullRef: fullRef, remote: nil)
        }

        guard fullRef.hasPrefix("refs/remotes/") else { return nil }
        let remainder = fullRef.dropFirst("refs/remotes/".count)
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let remote = String(remainder[..<slash])
        let name = String(remainder[remainder.index(after: slash)...])
        // Symbolic remote HEAD is not a branch — filter the ghost "origin/HEAD".
        guard name != "HEAD", !name.isEmpty, !remote.isEmpty else { return nil }
        return GitBranch(name: name, fullRef: fullRef, remote: remote)
    }

    // MARK: - Internals

    private static let baseEnvironment: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "LC_ALL": "C",
        "GIT_OPTIONAL_LOCKS": "0",
    ]

    private static let fetchEnvironment: [String: String] = baseEnvironment.merging([
        "GIT_SSH_COMMAND": "ssh -oBatchMode=yes -oStrictHostKeyChecking=accept-new",
    ]) { _, new in new }

    private func ensureRefExists(_ branch: GitBranch, in repository: GitRepository) async throws {
        let output = try await runGit(
            arguments: ["rev-parse", "--verify", "--quiet", "--end-of-options", branch.fullRef],
            workingDirectory: repository.rootURL
        )
        guard output.didSucceed else {
            throw GitError.branchNotFound(branch.displayName)
        }
    }

    private func runGit(
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = baseEnvironment
    ) async throws -> CommandOutput {
        let request = gitRequest(
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
        do {
            return try await runner.run(request)
        } catch let failure as CommandFailure {
            if case .launchFailed = failure {
                throw GitError.gitUnavailable
            }
            throw failure
        }
    }

    private func gitRequest(
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = baseEnvironment
    ) -> CommandRequest {
        CommandRequest(
            executable: "git",
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }
}
