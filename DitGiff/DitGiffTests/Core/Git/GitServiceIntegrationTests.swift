import Foundation
import Testing

@testable import DitGiff

/// Real `git` through `SystemCommandRunner`. Fixtures are built in a temp directory and
/// removed when the test finishes — parsing is proven against actual command output.
nonisolated struct GitServiceIntegrationTests {
    private let runner = SystemCommandRunner()

    @Test func openListBaseAndCountAgainstARealRepository() async throws {
        let fixture = try await RealGitFixture.make(runner: runner)
        defer { fixture.remove() }

        let service = GitService(runner: runner)

        #expect(await service.isGitAvailable())

        let nested = fixture.root.appendingPathComponent("nested/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let repository = try await service.openRepository(at: nested)
        #expect(
            repository.rootURL.resolvingSymlinksInPath().path
                == fixture.root.resolvingSymlinksInPath().path
        )
        #expect(repository.displayName == fixture.root.lastPathComponent)
        #expect(repository.head == .branch("feature"))

        let branches = try await service.listBranches(in: repository)
        let displayNames = Set(branches.map(\.displayName))
        #expect(displayNames.contains("main"))
        #expect(displayNames.contains("feature"))
        #expect(displayNames.contains { $0.hasSuffix("/HEAD") } == false)

        let originHEAD = try await service.originHEADRef(in: repository)
        #expect(originHEAD == nil)

        let base = try #require(
            GitBaseSelection.probableBase(
                among: branches,
                originHEADRef: originHEAD,
                currentBranchName: "feature"
            )
        )
        #expect(base.displayName == "main")

        let compare = try #require(branches.first { $0.displayName == "feature" && !$0.isRemote })
        let count = try await service.changedFileCount(
            in: repository,
            base: base,
            compare: compare
        )
        #expect(count == 1)
    }

    @Test func openRepositoryRejectsAFolderThatIsNotAGitRepo() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dit-giff-not-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.openRepository(at: folder)
        }
        #expect(thrown == .notARepository(folder))
    }

    @Test func openRepositoryRejectsARepositoryWithNoCommits() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dit-giff-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await runner.run(
            CommandRequest(
                executable: "git",
                arguments: ["init", "-b", "main"],
                workingDirectory: root,
                environment: RealGitFixture.gitEnvironment
            )
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.openRepository(at: root)
        }
        guard case let .repositoryHasNoCommits(url)? = thrown else {
            Issue.record("expected repositoryHasNoCommits, got \(String(describing: thrown))")
            return
        }
        #expect(
            url.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().path
        )
    }

    @Test func changedFileCountRejectsUnrelatedHistories() async throws {
        let fixture = try await RealGitFixture.make(runner: runner, includeOrphan: true)
        defer { fixture.remove() }

        let service = GitService(runner: runner)
        let repository = try await service.openRepository(at: fixture.root)
        let branches = try await service.listBranches(in: repository)
        let main = try #require(branches.first { $0.displayName == "main" && !$0.isRemote })
        let orphan = try #require(branches.first { $0.displayName == "orphan" && !$0.isRemote })

        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.changedFileCount(
                in: repository,
                base: main,
                compare: orphan
            )
        }
        #expect(thrown == .noCommonAncestor(base: "main", compare: "orphan"))
    }

    @Test func fetchAgainstALocalRemoteSucceeds() async throws {
        let fixture = try await RealGitFixture.make(runner: runner, withLocalRemote: true)
        defer { fixture.remove() }

        let service = GitService(runner: runner)
        let repository = try await service.openRepository(at: fixture.root)

        try await service.fetch(in: repository)

        let branches = try await service.listBranches(in: repository)
        #expect(branches.contains { $0.displayName == "origin/main" })
        #expect(branches.contains { $0.fullRef == "refs/remotes/origin/HEAD" } == false)

        let originHEAD = try await service.originHEADRef(in: repository)
        #expect(originHEAD == "refs/remotes/origin/main")

        let base = GitBaseSelection.probableBase(
            among: branches,
            originHEADRef: originHEAD,
            currentBranchName: "feature"
        )
        #expect(base?.fullRef == "refs/remotes/origin/main")
    }
}

// MARK: - Fixture

/// A throwaway repository with `main`, `feature`, and a file whose name contains spaces.
/// Built through the same `CommandRunner` seam the app uses.
private struct RealGitFixture {
    let root: URL
    private let remoteRoot: URL?

    static let gitEnvironment: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "LC_ALL": "C",
        "GIT_OPTIONAL_LOCKS": "0",
    ]

    static func make(
        runner: SystemCommandRunner,
        includeOrphan: Bool = false,
        withLocalRemote: Bool = false
    ) async throws -> RealGitFixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("dit-giff-fixture-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        var remoteRoot: URL?
        if withLocalRemote {
            let remoteURL = fm.temporaryDirectory
                .appendingPathComponent("dit-giff-remote-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: remoteURL, withIntermediateDirectories: true)
            remoteRoot = remoteURL
        }

        try await runGit(runner, in: root, "init", "-b", "main")
        try await runGit(
            runner,
            in: root,
            "-c", "user.email=test@dit-giff.local",
            "-c", "user.name=DitGiffTests",
            "commit", "--allow-empty", "-m", "initial"
        )

        try await runGit(runner, in: root, "checkout", "-b", "feature")
        let spaced = root.appendingPathComponent("file with spaces.txt")
        try "changed\n".write(to: spaced, atomically: true, encoding: .utf8)
        try await runGit(
            runner,
            in: root,
            "-c", "user.email=test@dit-giff.local",
            "-c", "user.name=DitGiffTests",
            "add", "file with spaces.txt"
        )
        try await runGit(
            runner,
            in: root,
            "-c", "user.email=test@dit-giff.local",
            "-c", "user.name=DitGiffTests",
            "commit", "-m", "add spaced file"
        )

        if includeOrphan {
            try await runGit(runner, in: root, "checkout", "--orphan", "orphan")
            try await runGit(
                runner,
                in: root,
                "-c", "user.email=test@dit-giff.local",
                "-c", "user.name=DitGiffTests",
                "commit", "--allow-empty", "-m", "orphan root"
            )
            try await runGit(runner, in: root, "checkout", "feature")
        }

        if let remoteRoot {
            try await runGit(runner, in: remoteRoot, "init", "--bare", "-b", "main")
            try await runGit(runner, in: root, "remote", "add", "origin", remoteRoot.path)
            try await runGit(runner, in: root, "push", "-u", "origin", "main")
            try await runGit(runner, in: root, "push", "origin", "feature")
            try await runGit(runner, in: root, "remote", "set-head", "origin", "main")
        }

        return RealGitFixture(root: root, remoteRoot: remoteRoot)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
        if let remoteRoot {
            try? FileManager.default.removeItem(at: remoteRoot)
        }
    }

    private static func runGit(
        _ runner: SystemCommandRunner,
        in directory: URL,
        _ arguments: String...
    ) async throws {
        let output = try await runner.run(
            CommandRequest(
                executable: "git",
                arguments: arguments,
                workingDirectory: directory,
                environment: gitEnvironment
            )
        )
        guard output.didSucceed else {
            let detail = output.standardError.isEmpty
                ? "exit \(output.exitCode)"
                : output.standardError
            throw FixtureError.commandFailed(arguments.joined(separator: " "), detail)
        }
    }

    private enum FixtureError: Error, CustomStringConvertible {
        case commandFailed(String, String)

        var description: String {
            switch self {
            case let .commandFailed(command, detail):
                "git \(command) failed: \(detail)"
            }
        }
    }
}
