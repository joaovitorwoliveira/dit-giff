import Foundation
import Testing

@testable import DitGiff

nonisolated struct GitServiceTests {

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dit-giff-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func repository(
        at rootURL: URL = URL(fileURLWithPath: "/repo/example-repo", isDirectory: true),
        head: GitHEAD = .branch("feature")
    ) -> GitRepository {
        GitRepository(rootURL: rootURL, displayName: rootURL.lastPathComponent, head: head)
    }

    private var nonInteractiveEnvironment: [String: String] {
        [
            "GIT_TERMINAL_PROMPT": "0",
            "LC_ALL": "C",
            "GIT_OPTIONAL_LOCKS": "0",
        ]
    }

    private var fetchEnvironment: [String: String] {
        nonInteractiveEnvironment.merging([
            "GIT_SSH_COMMAND": "ssh -oBatchMode=yes -oStrictHostKeyChecking=accept-new",
        ]) { _, new in new }
    }

    // MARK: - Availability

    @Test func isGitAvailableWhenVersionSucceeds() async throws {
        let runner = FakeCommandRunner()
        await runner.stub("git", ["--version"], standardOutput: "git version 2.51.0\n")
        let service = GitService(runner: runner)

        #expect(await service.isGitAvailable())
    }

    @Test func isGitUnavailableWhenLaunchFails() async {
        let runner = FakeCommandRunner()
        await runner.stubFailure(
            "git",
            ["--version"],
            .launchFailed(executable: "git", reason: "not found in PATH")
        )
        let service = GitService(runner: runner)

        #expect(await service.isGitAvailable() == false)
    }

    // MARK: - Open

    @Test func openRepositoryResolvesSubdirectoryToRoot() async throws {
        let runner = FakeCommandRunner()
        let repoURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let chosen = repoURL.appendingPathComponent("nested/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)

        await runner.stub(
            "git",
            ["rev-parse", "--show-toplevel"],
            standardOutput: "\(repoURL.path)\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "HEAD"],
            standardOutput: "abc123\n"
        )
        await runner.stub(
            "git",
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            standardOutput: "development\n"
        )

        let service = GitService(runner: runner)
        let repo = try await service.openRepository(at: chosen)

        #expect(repo.rootURL.path == repoURL.path)
        #expect(repo.displayName == repoURL.lastPathComponent)
        #expect(repo.head == .branch("development"))

        let requests = await runner.receivedRequests
        #expect(requests.first?.workingDirectory == chosen)
        #expect(requests.first?.environment == nonInteractiveEnvironment)
    }

    @Test func openRepositoryReportsDetachedHEAD() async throws {
        let runner = FakeCommandRunner()
        let repoURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        await runner.stub(
            "git",
            ["rev-parse", "--show-toplevel"],
            standardOutput: "\(repoURL.path)\n"
        )
        await runner.stub("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
        await runner.stub(
            "git",
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            exitCode: 1
        )

        let service = GitService(runner: runner)
        let repo = try await service.openRepository(at: repoURL)

        #expect(repo.head == .detached)
    }

    @Test func openRepositoryThrowsWhenPathDoesNotExist() async {
        let runner = FakeCommandRunner()
        let service = GitService(runner: runner)
        let missing = URL(fileURLWithPath: "/tmp/dit-giff-no-such-\(UUID().uuidString)")

        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.openRepository(at: missing)
        }
        #expect(thrown == .pathDoesNotExist(missing))
    }

    @Test func openRepositoryThrowsWhenNotARepository() async throws {
        let runner = FakeCommandRunner()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dit-giff-not-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        await runner.stub(
            "git",
            ["rev-parse", "--show-toplevel"],
            standardError: "fatal: not a git repository (or any of the parent directories): .git\n",
            exitCode: 128
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.openRepository(at: folder)
        }
        #expect(thrown == .notARepository(folder))
    }

    @Test func openRepositoryThrowsWhenRepositoryHasNoCommits() async throws {
        let runner = FakeCommandRunner()
        let repoURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        await runner.stub(
            "git",
            ["rev-parse", "--show-toplevel"],
            standardOutput: "\(repoURL.path)\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "HEAD"],
            exitCode: 1
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.openRepository(at: repoURL)
        }
        #expect(thrown == .repositoryHasNoCommits(repoURL))
    }

    @Test func openRepositoryThrowsWhenGitIsUnavailable() async throws {
        let runner = FakeCommandRunner()
        let repoURL = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        await runner.stubFailure(
            "git",
            ["rev-parse", "--show-toplevel"],
            .launchFailed(executable: "git", reason: "not found in PATH")
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.openRepository(at: repoURL)
        }
        #expect(thrown == .gitUnavailable)
    }

    // MARK: - Branches

    @Test func listBranchesParsesLocalsAndRemotesAndFiltersOriginHEAD() async throws {
        let runner = FakeCommandRunner()
        // Literal NUL-separated for-each-ref output, including the symbolic remote HEAD
        // and a fabricated local name with a space (git rejects those; the parser must not).
        // Realistic for-each-ref with %(refname)%00: NUL after each ref, newline between records.
        let stdout = [
            "refs/heads/branch with spaces",
            "refs/heads/development",
            "refs/heads/main",
            "refs/remotes/origin/HEAD",
            "refs/remotes/origin/development",
            "refs/remotes/origin/main",
        ].map { "\($0)\0\n" }.joined()

        await runner.stub(
            "git",
            ["for-each-ref", "--format=%(refname)%00", "refs/heads", "refs/remotes"],
            standardOutput: stdout
        )

        let service = GitService(runner: runner)
        let branches = try await service.listBranches(in: repository())

        #expect(branches.map(\.displayName) == [
            "branch with spaces",
            "development",
            "main",
            "origin/development",
            "origin/main",
        ])
        #expect(branches.contains { $0.fullRef.hasSuffix("/HEAD") } == false)
        #expect(branches.first { $0.name == "branch with spaces" }?.remote == nil)
        #expect(branches.first { $0.displayName == "origin/development" }?.remote == "origin")
    }

    @Test func originHEADRefReturnsSymbolicTarget() async throws {
        let runner = FakeCommandRunner()
        await runner.stub(
            "git",
            ["symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
            standardOutput: "refs/remotes/origin/main\n"
        )

        let service = GitService(runner: runner)
        let ref = try await service.originHEADRef(in: repository())

        #expect(ref == "refs/remotes/origin/main")
    }

    @Test func originHEADRefIsNilWhenMissing() async throws {
        let runner = FakeCommandRunner()
        await runner.stub(
            "git",
            ["symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
            exitCode: 1
        )

        let service = GitService(runner: runner)
        let ref = try await service.originHEADRef(in: repository())

        #expect(ref == nil)
    }

    // MARK: - Changed file count

    @Test func changedFileCountUsesThreeDotRangeAndCountsNULPaths() async throws {
        let runner = FakeCommandRunner()
        let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
        let compare = GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil)
        let range = "\(base.fullRef)...\(compare.fullRef)"

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", base.fullRef]
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", compare.fullRef]
        )
        await runner.stub(
            "git",
            ["diff", "--name-only", "-z", range],
            standardOutput: "Sources/A.swift\0file with spaces.txt\0nested/b.swift\0"
        )

        let service = GitService(runner: runner)
        let count = try await service.changedFileCount(
            in: repository(),
            base: base,
            compare: compare
        )

        #expect(count == 3)

        let requests = await runner.receivedRequests
        #expect(requests.last?.arguments == ["diff", "--name-only", "-z", range])
        #expect(requests.last?.environment == nonInteractiveEnvironment)
    }

    @Test func changedFileCountThrowsWhenBranchIsMissing() async {
        let runner = FakeCommandRunner()
        let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
        let compare = GitBranch(name: "gone", fullRef: "refs/heads/gone", remote: nil)

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", base.fullRef]
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", compare.fullRef],
            exitCode: 1
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.changedFileCount(
                in: repository(),
                base: base,
                compare: compare
            )
        }
        #expect(thrown == .branchNotFound(compare.displayName))
    }

    @Test func changedFileCountThrowsWhenHistoriesAreUnrelated() async throws {
        let runner = FakeCommandRunner()
        let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
        let compare = GitBranch(name: "orphan", fullRef: "refs/heads/orphan", remote: nil)
        let range = "\(base.fullRef)...\(compare.fullRef)"

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", base.fullRef]
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", compare.fullRef]
        )
        await runner.stub(
            "git",
            ["diff", "--name-only", "-z", range],
            standardError: "fatal: \(range): no merge base\n",
            exitCode: 128
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.changedFileCount(
                in: repository(),
                base: base,
                compare: compare
            )
        }
        #expect(thrown == .noCommonAncestor(base: "main", compare: "orphan"))
    }

    @Test func changedFileCountFailureDoesNotExposeRefsInTheMessage() async throws {
        let runner = FakeCommandRunner()
        let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
        let compare = GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil)
        let range = "\(base.fullRef)...\(compare.fullRef)"

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", base.fullRef]
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", compare.fullRef]
        )
        await runner.stub(
            "git",
            ["diff", "--name-only", "-z", range],
            standardError: "fatal: something else about \(range)\n",
            exitCode: 128
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.changedFileCount(
                in: repository(),
                base: base,
                compare: compare
            )
        }
        #expect(thrown == .couldNotCompare(base: "main", compare: "feature"))
        let message = thrown?.errorDescription ?? ""
        #expect(message.contains("refs/heads/") == false)
        #expect(message.contains("feature"))
        #expect(message.contains("main"))
    }

    // MARK: - Fetch

    @Test func fetchUsesNonInteractiveSSHEnvironment() async throws {
        let runner = FakeCommandRunner()
        await runner.stub("git", ["fetch", "--all", "--prune"])

        let service = GitService(runner: runner)
        try await service.fetch(in: repository())

        let requests = await runner.receivedRequests
        #expect(requests.count == 1)
        #expect(requests[0].arguments == ["fetch", "--all", "--prune"])
        #expect(requests[0].environment == fetchEnvironment)
        #expect(requests[0].workingDirectory == repository().rootURL)
    }

    @Test func fetchThrowsNamedFailureWithReason() async {
        let runner = FakeCommandRunner()
        await runner.stub(
            "git",
            ["fetch", "--all", "--prune"],
            standardError: "fatal: could not read from remote repository.\n",
            exitCode: 128
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            try await service.fetch(in: repository())
        }
        #expect(
            thrown == .fetchFailed(reason: "fatal: could not read from remote repository.")
        )
    }

    // MARK: - Error copy

    @Test func gitErrorMessagesAreActionableEnglish() {
        let path = URL(fileURLWithPath: "/tmp/x")
        #expect(GitError.pathDoesNotExist(path).errorDescription?.contains("/tmp/x") == true)
        #expect(GitError.notARepository(path).errorDescription?.contains("not a Git repository") == true)
        #expect(GitError.repositoryHasNoCommits(path).errorDescription?.contains("no commits") == true)
        #expect(GitError.branchNotFound("feature/x").errorDescription?.contains("not found") == true)
        #expect(GitError.branchNotFound("feature/x").errorDescription?.contains("refs/") == false)
        #expect(GitError.gitUnavailable.errorDescription?.contains("PATH") == true)
        #expect(GitError.fetchFailed(reason: "denied").errorDescription?.contains("denied") == true)
        #expect(
            GitError.fetchFailed(reason: "failed refs/heads/main remote")
                .errorDescription?.contains("refs/heads/") == false
        )
        #expect(
            GitError.noCommonAncestor(base: "a", compare: "b").errorDescription?
                .contains("no common ancestor") == true
        )
        #expect(
            GitError.couldNotCompare(base: "main", compare: "feature").errorDescription?
                .contains("refs/") == false
        )
        #expect(
            GitError.repositoryMovedOrDeleted(path).errorDescription?
                .contains("no longer") == true
        )
    }
}
