import Foundation
import Testing

@testable import DitGiff

nonisolated struct ReadingProgressStoreTests {

    private func makeStore() throws -> (store: ReadingProgressStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dit-giff-reading-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try ReadingProgressStore(directoryURL: directory)
        return (store, directory)
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func key(
        repo: String = "/Users/me/Code/dit-giff",
        base: String = "refs/heads/main",
        compare: String = "refs/heads/feature"
    ) -> ReadingProgressKey {
        ReadingProgressKey(repositoryPath: repo, baseRef: base, compareRef: compare)
    }

    private func sampleProgress(
        path: String = "src/A.swift",
        fingerprint: String = "abc",
        focused: String? = "src/A.swift"
    ) -> SessionReadingProgress {
        SessionReadingProgress(
            files: [
                FileReadingProgress(
                    path: path,
                    patchFingerprint: fingerprint,
                    isViewed: true,
                    readHunkIDs: ["hunk-1"],
                    isCollapsed: true
                )
            ],
            closedDirectories: ["src"],
            focusedFilePath: focused
        )
    }

    @Test func missingFileReturnsNilWithoutError() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        let loaded = try store.load(key: key())

        #expect(loaded == nil)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path) == false)
    }

    @Test func roundTripWriteAndRead() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        let progress = sampleProgress()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try store.save(key: key(), progress: progress, updatedAt: updatedAt)

        let loaded = try store.load(key: key())
        #expect(loaded == progress)

        // JSONEncoder may escape `/` as `\/`; assert on substrings that survive either form.
        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(raw.contains("\"schemaVersion\" : 1"))
        #expect(raw.contains("feature"))
        #expect(raw.contains("A.swift"))
    }

    @Test func twoKeysInSameFileDoNotMix() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        let keyA = key(compare: "refs/heads/a")
        let keyB = key(compare: "refs/heads/b")
        let progressA = sampleProgress(path: "A.swift", fingerprint: "fa", focused: "A.swift")
        let progressB = sampleProgress(path: "B.swift", fingerprint: "fb", focused: "B.swift")

        try store.save(key: keyA, progress: progressA, updatedAt: Date(timeIntervalSince1970: 1))
        try store.save(key: keyB, progress: progressB, updatedAt: Date(timeIntervalSince1970: 2))

        #expect(try store.load(key: keyA) == progressA)
        #expect(try store.load(key: keyB) == progressB)
    }

    @Test func savingSameKeyTwiceDoesNotDuplicate() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        let first = sampleProgress(fingerprint: "v1")
        let second = sampleProgress(fingerprint: "v2")
        try store.save(key: key(), progress: first, updatedAt: Date(timeIntervalSince1970: 1))
        try store.save(key: key(), progress: second, updatedAt: Date(timeIntervalSince1970: 2))

        #expect(try store.load(key: key()) == second)

        let data = try Data(contentsOf: store.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ReadingProgressDocument.self, from: data)
        #expect(document.entries.count == 1)
        #expect(document.entries[0].progress == second)
        #expect(document.entries[0].updatedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func exceedingLimitDropsTheOldestByUpdatedAt() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        for index in 1...33 {
            let entryKey = key(compare: "refs/heads/branch-\(index)")
            try store.save(
                key: entryKey,
                progress: sampleProgress(path: "f-\(index).swift", fingerprint: "fp-\(index)"),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        #expect(try store.load(key: key(compare: "refs/heads/branch-1")) == nil)
        #expect(try store.load(key: key(compare: "refs/heads/branch-2")) != nil)
        #expect(try store.load(key: key(compare: "refs/heads/branch-33")) != nil)

        let data = try Data(contentsOf: store.fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ReadingProgressDocument.self, from: data)
        #expect(document.entries.count == ReadingProgressStore.maxEntries)
        #expect(document.entries.contains { $0.key.compareRef == "refs/heads/branch-1" } == false)
    }

    @Test func fingerprintIsStableHexForKnownInput() {
        #expect(
            readingProgressFingerprint(for: "hello")
                == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        #expect(
            readingProgressFingerprint(for: "")
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test func corruptedFileThrowsNamedError() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        try "not-json-at-all".write(to: store.fileURL, atomically: true, encoding: .utf8)

        let thrown = #expect(throws: ReadingProgressStoreError.self) {
            _ = try store.load(key: key())
        }

        guard case .corrupted? = thrown else {
            Issue.record("expected corrupted, got \(String(describing: thrown))")
            return
        }
    }

    @Test func unsupportedSchemaVersionThrowsCorrupted() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        let json = """
        {
          "schemaVersion" : 99,
          "entries" : []
        }
        """
        try json.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let thrown = #expect(throws: ReadingProgressStoreError.self) {
            _ = try store.load(key: key())
        }

        guard case let .corrupted(reason)? = thrown else {
            Issue.record("expected corrupted, got \(String(describing: thrown))")
            return
        }
        #expect(reason.contains("99"))
    }
}
