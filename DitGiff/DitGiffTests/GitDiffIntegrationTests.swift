import Foundation
import Testing

@testable import DitGiff

/// Real `git` through `SystemCommandRunner`, plus FakeCommandRunner error paths for
/// the new diff APIs. Fixture is local to this file — do not share with GitServiceIntegrationTests.
nonisolated struct GitDiffIntegrationTests {
    private let runner = SystemCommandRunner()

    // MARK: - Real git envelopes

    @Test func diffFileEnvelopesCoversRequiredScenarios() async throws {
        let fixture = try await DiffGitFixture.make(runner: runner)
        defer { fixture.remove() }

        let service = GitService(runner: runner)
        let repository = try await service.openRepository(at: fixture.root)
        let branches = try await service.listBranches(in: repository)
        let base = try #require(branches.first { $0.displayName == "main" && !$0.isRemote })
        let compare = try #require(branches.first { $0.displayName == "feature" && !$0.isRemote })

        let envelopes = try await service.diffFileEnvelopes(
            in: repository,
            base: base,
            compare: compare
        )
        let byPath = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.path, $0) })

        // Modified
        let keep = try #require(byPath["keep.txt"])
        #expect(keep.change == .modified)
        guard case let .text(keepBody) = keep.body else {
            Issue.record("keep.txt should have a text body")
            return
        }
        #expect(keepBody.hasPrefix("@@"))
        #expect(keepBody.contains("+changed"))

        // Added
        let added = try #require(byPath["brand-new.txt"])
        #expect(added.change == .added)
        guard case let .text(addedBody) = added.body else {
            Issue.record("brand-new.txt should have a text body")
            return
        }
        #expect(addedBody.contains("+fresh"))

        // Deleted
        let gone = try #require(byPath["gone.txt"])
        #expect(gone.change == .deleted)
        guard case let .text(goneBody) = gone.body else {
            Issue.record("gone.txt should have a text body")
            return
        }
        #expect(goneBody.contains("-to-delete"))

        // Renamed
        let renamed = try #require(byPath["newname.txt"])
        #expect(renamed.change == .renamed(from: "oldname.txt"))
        #expect(renamed.oldPath == "oldname.txt")

        // Space in path
        let spaced = try #require(byPath["file with spaces.txt"])
        #expect(spaced.change == .added)
        guard case let .text(spacedBody) = spaced.body else {
            Issue.record("spaced file should have a text body")
            return
        }
        #expect(spacedBody.contains("+spaced"))

        // Accent in path
        let accent = try #require(byPath["arquivo café.txt"])
        #expect(accent.change == .added)
        guard case let .text(accentBody) = accent.body else {
            Issue.record("accent file should have a text body")
            return
        }
        #expect(accentBody.contains("+café"))

        // Binary
        let binary = try #require(byPath["binary.bin"])
        #expect(binary.change == .added)
        #expect(binary.body == .binary)

        // Mode-only
        let mode = try #require(byPath["mode.txt"])
        #expect(mode.change == .modified)
        #expect(mode.body == .noContent)
        #expect(mode.oldMode == "100644")
        #expect(mode.newMode == "100755")

        // No trailing newline
        let nonewline = try #require(byPath["nonewline.txt"])
        #expect(nonewline.change == .modified)
        guard case let .text(nonewlineBody) = nonewline.body else {
            Issue.record("nonewline.txt should have a text body")
            return
        }
        #expect(nonewlineBody.contains("\\ No newline at end of file"))
        #expect(nonewlineBody.contains("+no-nlX"))
    }

    @Test func diffPatchReturnsUnifiedTextMatchingEnvelopes() async throws {
        let fixture = try await DiffGitFixture.make(runner: runner)
        defer { fixture.remove() }

        let service = GitService(runner: runner)
        let repository = try await service.openRepository(at: fixture.root)
        let branches = try await service.listBranches(in: repository)
        let base = try #require(branches.first { $0.displayName == "main" && !$0.isRemote })
        let compare = try #require(branches.first { $0.displayName == "feature" && !$0.isRemote })

        let patch = try await service.diffPatch(in: repository, base: base, compare: compare)
        #expect(patch.contains("diff --git a/keep.txt b/keep.txt"))
        #expect(patch.contains("diff --git a/arquivo café.txt b/arquivo café.txt"))
        #expect(patch.contains("Binary files"))
        #expect(patch.contains("rename from oldname.txt"))
    }

    @Test func diffPatchRejectsUnrelatedHistories() async throws {
        let fixture = try await DiffGitFixture.make(runner: runner, includeOrphan: true)
        defer { fixture.remove() }

        let service = GitService(runner: runner)
        let repository = try await service.openRepository(at: fixture.root)
        let branches = try await service.listBranches(in: repository)
        let main = try #require(branches.first { $0.displayName == "main" && !$0.isRemote })
        let orphan = try #require(branches.first { $0.displayName == "orphan" && !$0.isRemote })

        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.diffPatch(in: repository, base: main, compare: orphan)
        }
        #expect(thrown == .noCommonAncestor(base: "main", compare: "orphan"))
    }

    // MARK: - FakeCommandRunner error paths

    @Test func diffPatchMapsMissingMergeBaseFromFakeRunner() async throws {
        let runner = FakeCommandRunner()
        let root = URL(fileURLWithPath: "/repo/example", isDirectory: true)
        let repository = GitRepository(rootURL: root, displayName: "example", head: .branch("feature"))
        let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
        let compare = GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil)
        let range = "\(base.fullRef)...\(compare.fullRef)"

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", base.fullRef],
            standardOutput: "abc\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", compare.fullRef],
            standardOutput: "def\n"
        )
        await runner.stub(
            "git",
            GitService.unifiedDiffArguments(range: range),
            standardError: "fatal: base...compare: no merge base\n",
            exitCode: 128
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.diffPatch(in: repository, base: base, compare: compare)
        }
        #expect(thrown == .noCommonAncestor(base: "main", compare: "feature"))
    }

    @Test func diffPatchMapsGenericCompareFailureFromFakeRunner() async throws {
        let runner = FakeCommandRunner()
        let root = URL(fileURLWithPath: "/repo/example", isDirectory: true)
        let repository = GitRepository(rootURL: root, displayName: "example", head: .branch("feature"))
        let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
        let compare = GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil)
        let range = "\(base.fullRef)...\(compare.fullRef)"

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", base.fullRef],
            standardOutput: "abc\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", compare.fullRef],
            standardOutput: "def\n"
        )
        await runner.stub(
            "git",
            GitService.unifiedDiffArguments(range: range),
            standardError: "fatal: bad object\n",
            exitCode: 128
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.diffPatch(in: repository, base: base, compare: compare)
        }
        #expect(thrown == .couldNotCompare(base: "main", compare: "feature"))
    }

    @Test func diffPatchMapsLaunchFailureToGitUnavailable() async throws {
        let runner = FakeCommandRunner()
        let root = URL(fileURLWithPath: "/repo/example", isDirectory: true)
        let repository = GitRepository(rootURL: root, displayName: "example", head: .branch("feature"))
        let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
        let compare = GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil)

        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", base.fullRef],
            standardOutput: "abc\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", compare.fullRef],
            standardOutput: "def\n"
        )
        await runner.stubFailure(
            "git",
            GitService.unifiedDiffArguments(range: "\(base.fullRef)...\(compare.fullRef)"),
            .launchFailed(executable: "git", reason: "not found in PATH")
        )

        let service = GitService(runner: runner)
        let thrown = await #expect(throws: GitError.self) {
            _ = try await service.diffPatch(in: repository, base: base, compare: compare)
        }
        #expect(thrown == .gitUnavailable)
    }
}

// MARK: - Fixture

/// Throwaway repo with the Slice-3 diff scenarios. Built through SystemCommandRunner.
private struct DiffGitFixture {
    let root: URL

    static let gitEnvironment: [String: String] = [
        "GIT_TERMINAL_PROMPT": "0",
        "LC_ALL": "C",
        "GIT_OPTIONAL_LOCKS": "0",
    ]

    static func make(
        runner: SystemCommandRunner,
        includeOrphan: Bool = false
    ) async throws -> DiffGitFixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("dit-giff-diff-fixture-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        try await runGit(runner, in: root, "init", "-b", "main")
        try await runGit(runner, in: root, "config", "core.filemode", "true")
        try await runGit(
            runner,
            in: root,
            "-c", "user.email=test@dit-giff.local",
            "-c", "user.name=DitGiffTests",
            "commit", "--allow-empty", "-m", "initial"
        )

        // Base tree on main
        try "content\n".write(
            to: root.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "oldname\n".write(
            to: root.appendingPathComponent("oldname.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "to-delete\n".write(
            to: root.appendingPathComponent("gone.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "mode-only\n".write(
            to: root.appendingPathComponent("mode.txt"),
            atomically: true,
            encoding: .utf8
        )
        let nonewlineURL = root.appendingPathComponent("nonewline.txt")
        try Data("no-nl".utf8).write(to: nonewlineURL)

        try await runGit(runner, in: root, "add", "-A")
        try await commit(runner, in: root, message: "base files")

        try await runGit(runner, in: root, "checkout", "-b", "feature")

        // Modified
        try "changed\n".write(
            to: root.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Renamed
        try await runGit(runner, in: root, "mv", "oldname.txt", "newname.txt")

        // Deleted
        try fm.removeItem(at: root.appendingPathComponent("gone.txt"))

        // Mode-only: change the working-tree bit so `git add -A` keeps 100755.
        let modeURL = root.appendingPathComponent("mode.txt")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: modeURL.path
        )

        // No trailing newline (still none)
        try Data("no-nlX".utf8).write(to: nonewlineURL)

        // Added text
        try "fresh\n".write(
            to: root.appendingPathComponent("brand-new.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Space in name
        try "spaced\n".write(
            to: root.appendingPathComponent("file with spaces.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Accent in name
        try "café\n".write(
            to: root.appendingPathComponent("arquivo café.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Binary
        try Data([0x00, 0x01, 0x02, 0x03, 0xFF]).write(
            to: root.appendingPathComponent("binary.bin")
        )

        try await runGit(runner, in: root, "add", "-A")
        try await commit(runner, in: root, message: "feature changes")

        if includeOrphan {
            try await runGit(runner, in: root, "checkout", "--orphan", "orphan")
            try await commit(runner, in: root, message: "orphan root", allowEmpty: true)
            try await runGit(runner, in: root, "checkout", "feature")
        }

        return DiffGitFixture(root: root)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func commit(
        _ runner: SystemCommandRunner,
        in directory: URL,
        message: String,
        allowEmpty: Bool = false
    ) async throws {
        var args = [
            "-c", "user.email=test@dit-giff.local",
            "-c", "user.name=DitGiffTests",
            "commit", "-m", message,
        ]
        if allowEmpty {
            args.insert("--allow-empty", at: args.count - 2)
        }
        try await runGit(runner, in: directory, args)
    }

    private static func runGit(
        _ runner: SystemCommandRunner,
        in directory: URL,
        _ arguments: String...
    ) async throws {
        try await runGit(runner, in: directory, Array(arguments))
    }

    private static func runGit(
        _ runner: SystemCommandRunner,
        in directory: URL,
        _ arguments: [String]
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
