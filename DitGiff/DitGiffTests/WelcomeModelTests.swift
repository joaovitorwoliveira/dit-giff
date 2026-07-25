import Foundation
import Testing

@testable import DitGiff

@MainActor
struct WelcomeModelTests {

    // MARK: - Harness

    private final class NullDirectoryPicker: DirectoryPicker {
        func pickDirectory() async -> URL? { nil }
    }

    /// Parks git calls whose first argument (or a later arg) matches until `releasePark` runs.
    private final class ParkingCommandRunner: CommandRunner, @unchecked Sendable {
        private let inner = FakeCommandRunner()
        private let lock = NSLock()
        private var parkMarker: String?
        private var parkContinuation: CheckedContinuation<Void, Never>?
        private var startedContinuation: CheckedContinuation<Void, Never>?

        func stub(
            _ executable: String,
            _ arguments: [String] = [],
            standardOutput: String = "",
            standardError: String = "",
            exitCode: Int32 = 0
        ) async {
            await inner.stub(
                executable,
                arguments,
                standardOutput: standardOutput,
                standardError: standardError,
                exitCode: exitCode
            )
        }

        func stubFailure(
            _ executable: String,
            _ arguments: [String] = [],
            _ failure: CommandFailure
        ) async {
            await inner.stubFailure(executable, arguments, failure)
        }

        func parkCommandsMatching(_ marker: String) {
            lock.lock()
            parkMarker = marker
            lock.unlock()
        }

        /// Backwards-compatible name used by the change-count race test.
        func parkDiffsMatching(_ marker: String) {
            parkCommandsMatching(marker)
        }

        func waitUntilParkStarts() async {
            lock.lock()
            if parkContinuation != nil {
                lock.unlock()
                return
            }
            lock.unlock()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if parkContinuation != nil {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                startedContinuation = continuation
                lock.unlock()
            }
        }

        func waitUntilParkedDiffStarts() async {
            await waitUntilParkStarts()
        }

        func releasePark() {
            lock.lock()
            let continuation = parkContinuation
            parkContinuation = nil
            lock.unlock()
            continuation?.resume()
        }

        func releaseDiff() {
            releasePark()
        }

        func run(_ request: CommandRequest) async throws -> CommandOutput {
            lock.lock()
            let marker = parkMarker
            let shouldPark = request.executable == "git"
                && marker.map { needle in request.arguments.contains { $0.contains(needle) } } == true
            lock.unlock()

            if shouldPark {
                lock.lock()
                let started = startedContinuation
                startedContinuation = nil
                lock.unlock()
                started?.resume()

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    parkContinuation = continuation
                    lock.unlock()
                }
            }
            return try await inner.run(request)
        }
    }

    @MainActor
    private struct Harness {
        let runner: ParkingCommandRunner
        let storeDirectory: URL
        let model: WelcomeModel
        let repoRoot: URL
        let secondRepoRoot: URL

        static func make() async throws -> Harness {
            let storeDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("dit-giff-welcome-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

            let repoRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("dit-giff-repo-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: repoRoot, withIntermediateDirectories: true)

            let secondRepoRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("dit-giff-repo-b-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: secondRepoRoot, withIntermediateDirectories: true)

            let runner = ParkingCommandRunner()
            let store = try RecentRepositoriesStore(directoryURL: storeDirectory)
            let model = WelcomeModel(
                git: GitService(runner: runner),
                recentStore: store,
                directoryPicker: NullDirectoryPicker()
            )
            return Harness(
                runner: runner,
                storeDirectory: storeDirectory,
                model: model,
                repoRoot: repoRoot,
                secondRepoRoot: secondRepoRoot
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: storeDirectory)
            try? FileManager.default.removeItem(at: repoRoot)
            try? FileManager.default.removeItem(at: secondRepoRoot)
        }

        func stubOpenSuccess(
            at root: URL? = nil,
            head: String = "feature",
            branches: [String] = [
                "refs/heads/main",
                "refs/heads/feature",
                "refs/heads/topic",
            ],
            originHEAD: String? = "refs/remotes/origin/main"
        ) async {
            let rootPath = (root ?? repoRoot).path
            await runner.stub(
                "git",
                ["rev-parse", "--show-toplevel"],
                standardOutput: "\(rootPath)\n"
            )
            await runner.stub("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
            await runner.stub(
                "git",
                ["symbolic-ref", "--quiet", "--short", "HEAD"],
                standardOutput: "\(head)\n"
            )
            let listed = branches.map { "\($0)\0\n" }.joined()
            await runner.stub(
                "git",
                ["for-each-ref", "--format=%(refname)%00", "refs/heads", "refs/remotes"],
                standardOutput: listed
            )
            if let originHEAD {
                await runner.stub(
                    "git",
                    ["symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
                    standardOutput: "\(originHEAD)\n"
                )
            } else {
                await runner.stub(
                    "git",
                    ["symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
                    exitCode: 1
                )
            }
        }

        func stubChangeCount(base: String, compare: String, count: Int) async {
            let range = "\(base)...\(compare)"
            await runner.stub(
                "git",
                ["rev-parse", "--verify", "--quiet", "--end-of-options", base]
            )
            await runner.stub(
                "git",
                ["rev-parse", "--verify", "--quiet", "--end-of-options", compare]
            )
            let files = (0..<count).map { "file\($0).swift" }.joined(separator: "\0") + (count > 0 ? "\0" : "")
            await runner.stub(
                "git",
                ["diff", "--name-only", "-z", range],
                standardOutput: files
            )
        }

        func seedRecent(at root: URL? = nil, displayName: String = "repo") throws {
            try RecentRepositoriesStore(directoryURL: storeDirectory).record(
                rootPath: (root ?? repoRoot).path,
                displayName: displayName
            )
        }

        func stubCurrentHEAD(branch: String) async {
            await runner.stub("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
            await runner.stub(
                "git",
                ["symbolic-ref", "--quiet", "--short", "HEAD"],
                standardOutput: "\(branch)\n"
            )
        }

        func stubDetachedHEAD() async {
            await runner.stub("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
            await runner.stub(
                "git",
                ["symbolic-ref", "--quiet", "--short", "HEAD"],
                exitCode: 1
            )
        }
    }

    // MARK: - Open

    @Test func openingAValidRepositoryPopulatesBranchesAndPreselectsBase() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: [
                "refs/heads/main",
                "refs/heads/feature",
                "refs/remotes/origin/main",
            ],
            originHEAD: "refs/remotes/origin/main"
        )
        await harness.stubChangeCount(
            base: "refs/remotes/origin/main",
            compare: "refs/heads/feature",
            count: 2
        )

        await harness.model.openRepository(at: harness.repoRoot)

        #expect(harness.model.selectedRepository?.displayName == harness.repoRoot.lastPathComponent)
        #expect(harness.model.branches.map(\.displayName).contains("main"))
        #expect(harness.model.branches.map(\.displayName).contains("feature"))
        #expect(harness.model.branches.map(\.displayName).contains("origin/main"))
        #expect(harness.model.baseBranch?.fullRef == "refs/remotes/origin/main")
        #expect(harness.model.compareBranch?.fullRef == "refs/heads/feature")
        #expect(harness.model.canOpenDiff)

        try await waitUntil(harness.model) { !$0.isCountingChanges }
        #expect(harness.model.changeSummary == "2 files")
    }

    @Test func openingASubfolderResolvesToTheRepositoryRoot() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        let nested = harness.repoRoot.appendingPathComponent("nested/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        await harness.stubOpenSuccess(
            branches: ["refs/heads/main", "refs/heads/feature"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )

        await harness.model.openRepository(at: nested)

        #expect(
            harness.model.selectedRepository?.rootURL.resolvingSymlinksInPath().path
                == harness.repoRoot.resolvingSymlinksInPath().path
        )
    }

    @Test func namedErrorWhenPathIsNotARepository() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("dit-giff-not-repo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        await harness.runner.stub(
            "git",
            ["rev-parse", "--show-toplevel"],
            standardError: "fatal: not a git repository\n",
            exitCode: 128
        )

        await harness.model.openRepository(at: folder)

        #expect(harness.model.selectedRepository == nil)
        #expect(harness.model.banner?.message.contains("not a Git repository") == true)
    }

    @Test func namedErrorWhenRepositoryHasNoCommits() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.runner.stub(
            "git",
            ["rev-parse", "--show-toplevel"],
            standardOutput: "\(harness.repoRoot.path)\n"
        )
        await harness.runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "HEAD"],
            exitCode: 1
        )

        await harness.model.openRepository(at: harness.repoRoot)

        #expect(harness.model.banner?.message.contains("no commits") == true)
    }

    @Test func namedErrorWhenGitIsUnavailable() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.runner.stubFailure(
            "git",
            ["rev-parse", "--show-toplevel"],
            .launchFailed(executable: "git", reason: "not found in PATH")
        )

        await harness.model.openRepository(at: harness.repoRoot)

        #expect(harness.model.banner?.message.contains("not available") == true)
    }

    @Test func missingRecentShowsMovedErrorWithRemoveAction() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        let missingPath = "/tmp/dit-giff-missing-\(UUID().uuidString)"
        try RecentRepositoriesStore(directoryURL: harness.storeDirectory).record(
            rootPath: missingPath,
            displayName: "gone"
        )
        harness.model.reloadRecents()

        let entry = try #require(harness.model.recentRepositories.first)
        #expect(entry.isAvailable == false)

        harness.model.selectRecent(entry)

        #expect(harness.model.banner?.message.contains("no longer") == true)
        #expect(harness.model.banner?.actionTitle == "Remove from list")
        #expect(harness.model.banner?.actionRootPath == missingPath)

        harness.model.performBannerAction()

        #expect(harness.model.recentRepositories.isEmpty)
        #expect(harness.model.banner == nil)
    }

    // MARK: - Recent HEAD labels

    @Test func recentHeadLabelFillsInAsynchronouslyWithoutBlockingTheList() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        try harness.seedRecent(displayName: "billing")
        await harness.stubCurrentHEAD(branch: "feature/annual-billing")

        harness.model.reloadRecents()

        let immediate = try #require(harness.model.recentRepositories.first)
        #expect(immediate.displayName == "billing")
        #expect(immediate.headLabel == nil)

        try await waitUntil(harness.model) {
            $0.recentRepositories.first?.headLabel == "feature/annual-billing"
        }
        #expect(harness.model.banner == nil)
    }

    @Test func detachedRecentHeadShowsAnHonestLabel() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        try harness.seedRecent()
        await harness.stubDetachedHEAD()
        harness.model.reloadRecents()

        try await waitUntil(harness.model) {
            $0.recentRepositories.first?.headLabel == "detached HEAD"
        }
    }

    @Test func failedRecentHeadReadLeavesTheLabelEmptyWithoutABanner() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        try harness.seedRecent()
        await harness.runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "HEAD"],
            exitCode: 1
        )
        harness.model.reloadRecents()

        try await Task.sleep(for: .milliseconds(80))
        #expect(harness.model.recentRepositories.first?.headLabel == nil)
        #expect(harness.model.banner == nil)
    }

    @Test func staleRecentHeadLoadDoesNotWriteAfterSessionBump() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        try harness.seedRecent()
        await harness.runner.stub("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
        await harness.runner.parkCommandsMatching("--short")
        harness.model.reloadRecents()
        await harness.runner.waitUntilParkStarts()
        #expect(harness.model.recentRepositories.first?.headLabel == nil)

        // Bump the repository session while the HEAD read is parked.
        harness.model.clearRepository()

        await harness.runner.stub(
            "git",
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            standardOutput: "should-not-appear\n"
        )
        await harness.runner.releasePark()
        try await Task.sleep(for: .milliseconds(80))

        #expect(harness.model.recentRepositories.first?.headLabel == nil)
        #expect(harness.model.banner == nil)
    }

    // MARK: - Change count

    @Test func changingEitherSelectorStartsANewCount() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: ["refs/heads/main", "refs/heads/feature", "refs/heads/topic"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )
        await harness.model.openRepository(at: harness.repoRoot)
        try await waitUntil(harness.model) { !$0.isCountingChanges }
        #expect(harness.model.changeSummary == "1 file")

        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/topic",
            count: 4
        )
        harness.model.selectCompare(displayName: "topic")
        try await waitUntil(harness.model) { !$0.isCountingChanges }
        #expect(harness.model.changeSummary == "4 files")

        await harness.stubChangeCount(
            base: "refs/heads/feature",
            compare: "refs/heads/topic",
            count: 9
        )
        harness.model.selectBase(displayName: "feature")
        try await waitUntil(harness.model) { !$0.isCountingChanges }
        #expect(harness.model.changeSummary == "9 files")
    }

    @Test func staleChangeCountDoesNotOverwriteANewerResult() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            head: "main",
            branches: ["refs/heads/main", "refs/heads/feature", "refs/heads/topic"],
            originHEAD: nil
        )
        await harness.model.openRepository(at: harness.repoRoot)
        #expect(harness.model.compareBranch == nil)

        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 3
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/topic",
            count: 7
        )

        await harness.runner.parkDiffsMatching("refs/heads/feature")
        harness.model.selectCompare(displayName: "feature")
        await harness.runner.waitUntilParkedDiffStarts()
        #expect(harness.model.isCountingChanges)
        #expect(harness.model.changeSummary == WelcomeSampleData.countingChangeSummary)

        // Newer selection — must win even if the parked feature count finishes later.
        harness.model.selectCompare(displayName: "topic")
        try await waitUntil(harness.model) { !$0.isCountingChanges && $0.changeSummary == "7 files" }

        await harness.runner.releaseDiff()
        try await Task.sleep(for: .milliseconds(80))

        #expect(harness.model.compareBranch?.displayName == "topic")
        #expect(harness.model.changeSummary == "7 files")
    }

    // MARK: - Recents

    @Test func openingRegistersInRecentsWithoutDuplicating() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: ["refs/heads/main", "refs/heads/feature"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 0
        )

        await harness.model.openRepository(at: harness.repoRoot)
        await harness.model.openRepository(at: harness.repoRoot)

        #expect(harness.model.recentRepositories.count == 1)
        #expect(harness.model.recentRepositories[0].rootPath == harness.repoRoot.path)
    }

    // MARK: - Fetch

    @Test func successfulFetchReloadsBranches() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: ["refs/heads/main", "refs/heads/feature"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )
        await harness.model.openRepository(at: harness.repoRoot)

        await harness.runner.stub("git", ["fetch", "--all", "--prune"])
        await harness.runner.stub(
            "git",
            ["for-each-ref", "--format=%(refname)%00", "refs/heads", "refs/remotes"],
            standardOutput: "refs/heads/main\0\nrefs/heads/feature\0\nrefs/remotes/origin/main\0\n"
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )

        harness.model.fetch()
        try await waitUntil(harness.model) { !$0.isFetching }

        #expect(harness.model.branches.map(\.displayName).contains("origin/main"))
        #expect(harness.model.banner == nil)
    }

    @Test func failedFetchShowsAnErrorBanner() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: ["refs/heads/main", "refs/heads/feature"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )
        await harness.model.openRepository(at: harness.repoRoot)

        await harness.runner.stub(
            "git",
            ["fetch", "--all", "--prune"],
            standardError: "fatal: could not read from remote repository.\n",
            exitCode: 128
        )

        harness.model.fetch()
        try await waitUntil(harness.model) { !$0.isFetching }

        #expect(harness.model.banner?.message.contains("Could not fetch") == true)
    }

    // MARK: - Session

    @Test func openDiffSessionCarriesRepositoryBaseAndCompare() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: ["refs/heads/main", "refs/heads/feature"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )
        await harness.model.openRepository(at: harness.repoRoot)
        harness.model.goal = "Ship the welcome wiring."
        harness.model.attachSpec()

        let session = try #require(harness.model.makeSession())
        #expect(session.repository.rootURL.path == harness.repoRoot.path)
        #expect(session.base.displayName == "main")
        #expect(session.compare.displayName == "feature")
        #expect(session.goal == "Ship the welcome wiring.")
        #expect(session.attachedSpecName == WelcomeSampleData.sampleSpecName)

        let app = AppModel(welcomeModel: harness.model, diffModel: DiffModel())
        app.openDiff(session)

        #expect(app.route == .diff)
        #expect(app.activeDiffSession == session)
    }

    @Test func clearingRepositoryResetsGoalAndSpec() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: ["refs/heads/main", "refs/heads/feature"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 0
        )
        await harness.model.openRepository(at: harness.repoRoot)
        harness.model.goal = "Something"
        harness.model.attachSpec()

        harness.model.clearRepository()

        #expect(harness.model.selectedRepository == nil)
        #expect(harness.model.compareBranch == nil)
        #expect(harness.model.goal.isEmpty)
        #expect(harness.model.attachedSpecName == nil)
        #expect(harness.model.canOpenDiff == false)
    }

    // MARK: - Session invalidation

    @Test func inFlightFetchDoesNotContaminateASwitchedRepository() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            at: harness.repoRoot,
            branches: ["refs/heads/main", "refs/heads/feature"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )
        await harness.model.openRepository(at: harness.repoRoot)

        await harness.runner.stub("git", ["fetch", "--all", "--prune"])
        await harness.runner.parkCommandsMatching("fetch")
        harness.model.fetch()
        await harness.runner.waitUntilParkStarts()
        #expect(harness.model.isFetching)

        // Switch to B while A's fetch is still parked. After release, A's listBranches
        // returns a marker branch that must not appear on B.
        await harness.stubOpenSuccess(
            at: harness.secondRepoRoot,
            head: "work",
            branches: ["refs/heads/trunk", "refs/heads/work"],
            originHEAD: nil
        )
        await harness.stubChangeCount(
            base: "refs/heads/trunk",
            compare: "refs/heads/work",
            count: 2
        )
        await harness.model.openRepository(at: harness.secondRepoRoot)
        #expect(harness.model.selectedRepository?.rootURL.path == harness.secondRepoRoot.path)
        #expect(Set(harness.model.branches.map(\.displayName)) == ["trunk", "work"])

        await harness.runner.stub(
            "git",
            ["for-each-ref", "--format=%(refname)%00", "refs/heads", "refs/remotes"],
            standardOutput: "refs/heads/main\0\nrefs/heads/only-from-fetch-of-a\0\n"
        )
        await harness.runner.releasePark()
        try await Task.sleep(for: .milliseconds(80))

        #expect(harness.model.selectedRepository?.rootURL.path == harness.secondRepoRoot.path)
        #expect(Set(harness.model.branches.map(\.displayName)) == ["trunk", "work"])
        #expect(harness.model.branches.map(\.displayName).contains("only-from-fetch-of-a") == false)
    }

    @Test func concurrentOpensKeepBranchesCoherentWithTheSelectedRepository() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            at: harness.repoRoot,
            head: "feature",
            branches: ["refs/heads/main", "refs/heads/only-in-a"],
            originHEAD: nil
        )

        // Park A's listBranches. B then completes fully; releasing A without a session
        // token would re-select A over B.
        await harness.runner.parkCommandsMatching("for-each-ref")
        let firstOpen = Task { await harness.model.openRepository(at: harness.repoRoot) }
        await harness.runner.waitUntilParkStarts()

        await harness.runner.parkCommandsMatching("___never___")
        await harness.stubOpenSuccess(
            at: harness.secondRepoRoot,
            head: "work",
            branches: ["refs/heads/trunk", "refs/heads/only-in-b"],
            originHEAD: nil
        )
        await harness.model.openRepository(at: harness.secondRepoRoot)

        #expect(harness.model.selectedRepository?.rootURL.path == harness.secondRepoRoot.path)
        #expect(harness.model.branches.map(\.displayName).contains("only-in-b"))

        await harness.runner.releasePark()
        _ = await firstOpen.value
        try await Task.sleep(for: .milliseconds(80))

        #expect(harness.model.selectedRepository?.rootURL.path == harness.secondRepoRoot.path)
        #expect(Set(harness.model.branches.map(\.displayName)) == ["trunk", "only-in-b"])
        #expect(harness.model.branches.map(\.displayName).contains("only-in-a") == false)
    }

    @Test func listBranchesFailureDoesNotLeaveAHybridSelection() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.runner.stub(
            "git",
            ["rev-parse", "--show-toplevel"],
            standardOutput: "\(harness.repoRoot.path)\n"
        )
        await harness.runner.stub("git", ["rev-parse", "--verify", "--quiet", "HEAD"])
        await harness.runner.stub(
            "git",
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            standardOutput: "main\n"
        )
        await harness.runner.stub(
            "git",
            ["for-each-ref", "--format=%(refname)%00", "refs/heads", "refs/remotes"],
            standardError: "fatal: bad packed-refs\n",
            exitCode: 128
        )

        await harness.model.openRepository(at: harness.repoRoot)

        #expect(harness.model.selectedRepository == nil)
        #expect(harness.model.branches.isEmpty)
        #expect(harness.model.baseBranch == nil)
        #expect(harness.model.compareBranch == nil)
        #expect(harness.model.banner != nil)
    }

    @Test func prunedBaseDoesNotRemainSelectedAsAGhost() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        await harness.stubOpenSuccess(
            branches: [
                "refs/heads/main",
                "refs/heads/feature",
                "refs/remotes/origin/feature-x",
            ],
            originHEAD: "refs/remotes/origin/feature-x"
        )
        await harness.stubChangeCount(
            base: "refs/remotes/origin/feature-x",
            compare: "refs/heads/feature",
            count: 1
        )
        await harness.model.openRepository(at: harness.repoRoot)
        #expect(harness.model.baseBranch?.displayName == "origin/feature-x")

        await harness.runner.stub("git", ["fetch", "--all", "--prune"])
        await harness.runner.stub(
            "git",
            ["for-each-ref", "--format=%(refname)%00", "refs/heads", "refs/remotes"],
            standardOutput: "refs/heads/main\0\nrefs/heads/feature\0\n"
        )
        await harness.runner.stub(
            "git",
            ["symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
            exitCode: 1
        )
        await harness.stubChangeCount(
            base: "refs/heads/main",
            compare: "refs/heads/feature",
            count: 1
        )

        harness.model.fetch()
        try await waitUntil(harness.model) { !$0.isFetching }

        #expect(harness.model.baseBranch?.fullRef != "refs/remotes/origin/feature-x")
        #expect(harness.model.baseBranch?.displayName == "main")
        #expect(harness.model.branches.map(\.displayName).contains("origin/feature-x") == false)
    }

    @Test func dropFailureProducesAVisibleBanner() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanup() }

        harness.model.reportDropFailure("Could not read that drop.")

        #expect(harness.model.banner?.message.contains("Could not read that drop") == true)
    }

    // MARK: - Helpers

    private func waitUntil(
        _ model: WelcomeModel,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        _ predicate: (WelcomeModel) -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !predicate(model) {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                Issue.record("Timed out waiting for WelcomeModel condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
