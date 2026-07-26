import Foundation
import Testing

@testable import DitGiff

/// Reading progress wired through `DiffModel`: real store on a temp directory, canned
/// git diffs via `FakeCommandRunner`. Write counts come from a store fake, not the model.
@MainActor
struct DiffModelProgressTests {

    // MARK: - Harness

    /// Forwards to a real `ReadingProgressStore` and counts `save` calls.
    private final class CountingReadingProgressStore: ReadingProgressStoring, @unchecked Sendable {
        let inner: ReadingProgressStore
        private(set) var saveCount = 0

        init(inner: ReadingProgressStore) {
            self.inner = inner
        }

        func load(key: ReadingProgressKey) throws -> SessionReadingProgress? {
            try inner.load(key: key)
        }

        func save(
            key: ReadingProgressKey,
            progress: SessionReadingProgress,
            updatedAt: Date
        ) throws {
            saveCount += 1
            try inner.save(key: key, progress: progress, updatedAt: updatedAt)
        }
    }

    /// Store that always fails on load — restore must surface an error and start clean.
    private struct FailingLoadStore: ReadingProgressStoring {
        func load(key: ReadingProgressKey) throws -> SessionReadingProgress? {
            throw ReadingProgressStoreError.corrupted(reason: "fixture: unreadable JSON")
        }

        func save(
            key: ReadingProgressKey,
            progress: SessionReadingProgress,
            updatedAt: Date
        ) throws {}
    }

    @MainActor
    private final class ProgressHarness {
        let directory: URL
        let store: ReadingProgressStore
        let countingStore: CountingReadingProgressStore
        let runner: FakeCommandRunner
        let model: DiffModel

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "dit-giff-progress-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            store = try ReadingProgressStore(directoryURL: directory)
            countingStore = CountingReadingProgressStore(inner: store)
            runner = FakeCommandRunner()
            model = DiffModel(
                git: GitService(runner: runner),
                readingProgressStore: countingStore
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func session(
        displayName: String = "billing-service",
        rootPath: String? = nil,
        baseName: String = "main",
        compareName: String = "feature"
    ) -> DiffSession {
        let root = rootPath ?? "/repo/\(displayName)"
        return DiffSession(
            repository: GitRepository(
                rootURL: URL(fileURLWithPath: root, isDirectory: true),
                displayName: displayName,
                head: .branch(compareName)
            ),
            base: GitBranch(
                name: baseName,
                fullRef: "refs/heads/\(baseName)",
                remote: nil
            ),
            compare: GitBranch(
                name: compareName,
                fullRef: "refs/heads/\(compareName)",
                remote: nil
            ),
            goal: "",
            attachedSpecName: nil
        )
    }

    private func stubPatch(
        on runner: FakeCommandRunner,
        session: DiffSession,
        unified: String,
        raw: String
    ) async {
        let range = "\(session.base.fullRef)...\(session.compare.fullRef)"
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", session.base.fullRef],
            standardOutput: "abc\n"
        )
        await runner.stub(
            "git",
            ["rev-parse", "--verify", "--quiet", "--end-of-options", session.compare.fullRef],
            standardOutput: "def\n"
        )
        await runner.stub(
            "git",
            GitService.unifiedDiffArguments(range: range),
            standardOutput: unified
        )
        await runner.stub(
            "git",
            GitService.rawDiffArguments(range: range),
            standardOutput: raw
        )
    }

    private func singleFilePatch(
        path: String = "Sources/A.swift",
        oldLine: String = "old",
        newLine: String = "new"
    ) -> (unified: String, raw: String) {
        let unified = """
        diff --git a/\(path) b/\(path)
        index d95f3ad..5ea2ed4 100644
        --- a/\(path)
        +++ b/\(path)
        @@ -1 +1 @@
        -\(oldLine)
        +\(newLine)
        """
        let raw = ":100644 100644 d95f3ad 5ea2ed4 M\0\(path)\0"
        return (unified, raw)
    }

    private func twoFilePatch(
        pathA: String = "Sources/Billing/A.swift",
        pathB: String = "Sources/Billing/B.swift",
        bodyA: (old: String, new: String) = ("old-a", "new-a"),
        bodyB: (old: String, new: String) = ("old-b", "new-b")
    ) -> (unified: String, raw: String) {
        let unified = """
        diff --git a/\(pathA) b/\(pathA)
        index aaa1111..aaa2222 100644
        --- a/\(pathA)
        +++ b/\(pathA)
        @@ -1 +1 @@
        -\(bodyA.old)
        +\(bodyA.new)
        diff --git a/\(pathB) b/\(pathB)
        index bbb1111..bbb2222 100644
        --- a/\(pathB)
        +++ b/\(pathB)
        @@ -1 +1 @@
        -\(bodyB.old)
        +\(bodyB.new)
        """
        let raw = """
        :100644 100644 aaa1111 aaa2222 M\0\(pathA)\0\
        :100644 100644 bbb1111 bbb2222 M\0\(pathB)\0
        """
        return (unified, raw)
    }

    private func twoHunkFilePatch(
        path: String = "Sources/A.swift"
    ) -> (unified: String, raw: String) {
        let unified = """
        diff --git a/\(path) b/\(path)
        index d95f3ad..5ea2ed4 100644
        --- a/\(path)
        +++ b/\(path)
        @@ -1 +1 @@
        -old-one
        +new-one
        @@ -10 +10 @@
        -old-two
        +new-two
        """
        let raw = ":100644 100644 d95f3ad 5ea2ed4 M\0\(path)\0"
        return (unified, raw)
    }

    private func binaryPatch(
        path: String = "Assets/logo.png",
        oldBlob: String,
        newBlob: String
    ) -> (unified: String, raw: String) {
        let unified = """
        diff --git a/\(path) b/\(path)
        index \(oldBlob)..\(newBlob) 100644
        Binary files a/\(path) and b/\(path) differ
        """
        let raw = ":100644 100644 \(oldBlob) \(newBlob) M\0\(path)\0"
        return (unified, raw)
    }

    private func load(
        _ model: DiffModel,
        session: DiffSession,
        on runner: FakeCommandRunner,
        unified: String,
        raw: String
    ) async {
        await stubPatch(on: runner, session: session, unified: unified, raw: raw)
        model.load(session)
        await model.pendingLoad?.value
        #expect(model.loadState == .loaded)
    }

    // MARK: - Save and restore

    @Test func markingViewedSavesAndRestoresOnSameKey() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let patch = singleFilePatch()
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        let file = try #require(harness.model.files.first)
        harness.model.setViewed(true, for: file)
        #expect(harness.model.viewedPaths.contains(file.path))
        #expect(harness.countingStore.saveCount == 1)
        #expect(harness.model.readingProgressError == nil)

        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        #expect(reopened.viewedPaths.contains(file.path))
        #expect(reopened.collapsedPaths.contains(file.path))
        #expect(reopened.focusedFilePath == nil)
    }

    @Test func differentRepositoryOrBranchDoesNotSeeOtherProgress() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let sessionA = session(rootPath: "/repo/a", compareName: "feature")
        let patch = singleFilePatch()
        await load(
            harness.model,
            session: sessionA,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )
        let file = try #require(harness.model.files.first)
        harness.model.setViewed(true, for: file)

        let otherRepo = session(rootPath: "/repo/b", compareName: "feature")
        let otherBranch = session(rootPath: "/repo/a", compareName: "topic")

        for other in [otherRepo, otherBranch] {
            let model = DiffModel(
                git: GitService(runner: harness.runner),
                readingProgressStore: harness.store
            )
            await load(
                model,
                session: other,
                on: harness.runner,
                unified: patch.unified,
                raw: patch.raw
            )
            #expect(model.viewedPaths.isEmpty)
            #expect(model.collapsedPaths.isEmpty)
        }
    }

    @Test func changedPatchFingerprintDropsThatFileWhileOthersSurvive() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let pathA = "Sources/Billing/A.swift"
        let pathB = "Sources/Billing/B.swift"
        let original = twoFilePatch(pathA: pathA, pathB: pathB)
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: original.unified,
            raw: original.raw
        )

        let fileA = try #require(harness.model.file(atPath: pathA))
        let fileB = try #require(harness.model.file(atPath: pathB))
        harness.model.setViewed(true, for: fileA)
        harness.model.setViewed(true, for: fileB)

        let changed = twoFilePatch(
            pathA: pathA,
            pathB: pathB,
            bodyA: ("old-a", "changed-a"),
            bodyB: ("old-b", "new-b")
        )
        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: changed.unified,
            raw: changed.raw
        )

        #expect(reopened.viewedPaths.contains(pathA) == false)
        #expect(reopened.viewedPaths.contains(pathB))
        #expect(reopened.collapsedPaths.contains(pathB))
    }

    @Test func fileGoneFromDiffLeavesNoStaleProgress() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let pathA = "Sources/Billing/A.swift"
        let pathB = "Sources/Billing/B.swift"
        let original = twoFilePatch(pathA: pathA, pathB: pathB)
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: original.unified,
            raw: original.raw
        )
        harness.model.setViewed(true, for: try #require(harness.model.file(atPath: pathA)))
        harness.model.setViewed(true, for: try #require(harness.model.file(atPath: pathB)))

        let onlyB = singleFilePatch(path: pathB, oldLine: "old-b", newLine: "new-b")
        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: onlyB.unified,
            raw: onlyB.raw
        )

        #expect(reopened.files.map(\.path) == [pathB])
        #expect(reopened.viewedPaths == [pathB])
        #expect(reopened.viewedPaths.contains(pathA) == false)
    }

    @Test func invalidFocusedPathBecomesNilOnRestore() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let path = "Sources/A.swift"
        let patch = singleFilePatch(path: path)
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        let file = try #require(harness.model.file(atPath: path))
        harness.model.revealFileInReader(file)
        harness.model.setViewed(true, for: file)
        #expect(harness.model.focusedFilePath == path)

        // Seed a focused path that will not exist in the next patch.
        let key = try #require(harness.model.progressKey)
        let fingerprint = harness.model.readingFingerprint(for: file)
        try harness.store.save(
            key: key,
            progress: SessionReadingProgress(
                files: [
                    FileReadingProgress(
                        path: path,
                        patchFingerprint: fingerprint,
                        isViewed: true,
                        readHunkIDs: [],
                        isCollapsed: true
                    )
                ],
                closedDirectories: [],
                focusedFilePath: "Sources/Gone.swift"
            )
        )

        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        #expect(reopened.viewedPaths.contains(path))
        #expect(reopened.focusedFilePath == nil)
        #expect(reopened.readerScrollRequest == nil)
    }

    @Test func folderViewedActionWritesOnce() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let pathA = "Sources/Billing/A.swift"
        let pathB = "Sources/Billing/B.swift"
        let patch = twoFilePatch(pathA: pathA, pathB: pathB)
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        let directory = try #require(
            harness.model.fileTree.compactMap { node -> DiffTreeDirectory? in
                guard case let .directory(directory) = node else { return nil }
                return directory
            }.first { $0.path == "Sources/" }
            .flatMap { sources in
                sources.children.compactMap { node -> DiffTreeDirectory? in
                    guard case let .directory(directory) = node else { return nil }
                    return directory
                }.first { $0.path == "Sources/Billing/" }
            }
        )

        let savesBefore = harness.countingStore.saveCount
        harness.model.toggleViewed(in: directory)

        #expect(harness.countingStore.saveCount == savesBefore + 1)
        #expect(directory.descendantFiles.allSatisfy(harness.model.isViewed))
    }

    @Test func sampleModeNeverReadsOrWritesTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "dit-giff-sample-progress-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try ReadingProgressStore(directoryURL: directory)
        let key = ReadingProgressKey(
            repositoryPath: "/should-not-touch",
            baseRef: "refs/heads/main",
            compareRef: "refs/heads/feature"
        )
        try store.save(
            key: key,
            progress: SessionReadingProgress(
                files: [
                    FileReadingProgress(
                        path: "Sources/Billing/BillingGuard.swift",
                        patchFingerprint: "poison",
                        isViewed: true,
                        readHunkIDs: [],
                        isCollapsed: true
                    )
                ],
                closedDirectories: ["Sources/"],
                focusedFilePath: "Sources/Billing/BillingGuard.swift"
            )
        )

        let sample = DiffModel()
        #expect(sample.usesSampleData)
        #expect(sample.readingProgressStore == nil)

        let before = try String(contentsOf: store.fileURL, encoding: .utf8)
        let billing = try #require(
            sample.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        sample.setViewed(false, for: billing)
        sample.toggleDirectory("Sources/")
        if let hunk = billing.hunks.first {
            sample.toggleRead(hunk)
        }

        let after = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(after == before)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        // Sample load is a no-op — even with a live-looking session, store stays untouched.
        sample.load(
            session(rootPath: "/should-not-touch", baseName: "main", compareName: "feature")
        )
        let afterLoad = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(afterLoad == before)
        #expect(sample.viewedPaths.contains(billing.path) == false)
    }

    @Test func restoredFocusRevealsFileInReader() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let path = "Sources/A.swift"
        let patch = singleFilePatch(path: path)
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        let file = try #require(harness.model.file(atPath: path))
        harness.model.revealFileInReader(file)
        harness.model.setViewed(true, for: file)

        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        #expect(reopened.focusedFilePath == path)
        #expect(reopened.readerScrollRequest?.path == path)
    }

    /// Focus alone must survive relaunch — without a neighbouring setViewed that
    /// accidentally writes the session.
    @Test func revealAlonePersistsFocusAcrossRelaunch() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let path = "Sources/A.swift"
        let patch = singleFilePatch(path: path)
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        let file = try #require(harness.model.file(atPath: path))
        let savesBefore = harness.countingStore.saveCount
        harness.model.revealFileInReader(file)
        #expect(harness.countingStore.saveCount == savesBefore + 1)
        #expect(harness.model.focusedFilePath == path)
        #expect(harness.model.viewedPaths.isEmpty)
        #expect(harness.model.readHunkIDs.isEmpty)

        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        #expect(reopened.focusedFilePath == path)
        #expect(reopened.readerScrollRequest?.path == path)
        #expect(reopened.viewedPaths.isEmpty)
    }

    @Test func partialReadHunkIDsSurviveIdenticalPatch() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let path = "Sources/A.swift"
        let patch = twoHunkFilePatch(path: path)
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        let file = try #require(harness.model.file(atPath: path))
        #expect(file.hunks.count == 2)
        let firstHunk = try #require(file.hunks.first)
        let secondHunk = try #require(file.hunks.last)
        harness.model.toggleRead(firstHunk)
        #expect(harness.model.readHunkIDs == [firstHunk.id])
        #expect(harness.model.readHunkIDs.contains(secondHunk.id) == false)

        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: patch.unified,
            raw: patch.raw
        )

        #expect(reopened.readHunkIDs == [firstHunk.id])
        #expect(reopened.readHunkIDs.contains(secondHunk.id) == false)
        #expect(reopened.viewedPaths.isEmpty)
    }

    @Test func binaryBlobIndexChangeDropsViewedMark() async throws {
        let harness = try ProgressHarness()
        defer { harness.cleanup() }

        let session = session()
        let path = "Assets/logo.png"
        let original = binaryPatch(path: path, oldBlob: "a1b2c3d", newBlob: "d4e5f6a")
        await load(
            harness.model,
            session: session,
            on: harness.runner,
            unified: original.unified,
            raw: original.raw
        )

        let file = try #require(harness.model.file(atPath: path))
        #expect(file.body == .binary)
        #expect(harness.model.filePatchBodies[path] == nil)
        #expect(harness.model.filePatchHeaders[path]?.contains("index a1b2c3d..d4e5f6a") == true)
        harness.model.setViewed(true, for: file)
        #expect(harness.model.viewedPaths.contains(path))

        // Same path and status; only the index blob SHAs change — the failure mode
        // of the old status|path descriptor.
        let changed = binaryPatch(path: path, oldBlob: "a1b2c3d", newBlob: "9999999")
        let reopened = DiffModel(
            git: GitService(runner: harness.runner),
            readingProgressStore: harness.store
        )
        await load(
            reopened,
            session: session,
            on: harness.runner,
            unified: changed.unified,
            raw: changed.raw
        )

        #expect(reopened.viewedPaths.contains(path) == false)
        #expect(reopened.collapsedPaths.contains(path) == false)
        #expect(reopened.filePatchHeaders[path]?.contains("index a1b2c3d..9999999") == true)
    }

    @Test func unreadableProgressSurfacesErrorAndStartsClean() async throws {
        let runner = FakeCommandRunner()
        let model = DiffModel(
            git: GitService(runner: runner),
            readingProgressStore: FailingLoadStore()
        )
        let session = session()
        let patch = singleFilePatch()
        await load(
            model,
            session: session,
            on: runner,
            unified: patch.unified,
            raw: patch.raw
        )

        let error = try #require(model.readingProgressError)
        #expect(error.contains("Saved reading progress could not be read"))
        #expect(error.contains("Starting this review clean"))
        #expect(model.viewedPaths.isEmpty)

        model.clearReadingProgressError()
        #expect(model.readingProgressError == nil)
    }
}
