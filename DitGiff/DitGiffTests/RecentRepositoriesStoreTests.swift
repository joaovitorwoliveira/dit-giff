import Foundation
import Testing

@testable import DitGiff

nonisolated struct RecentRepositoriesStoreTests {

    private func makeStore() throws -> (store: RecentRepositoriesStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dit-giff-recent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try RecentRepositoriesStore(directoryURL: directory)
        return (store, directory)
    }

    private func cleanup(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func missingFileReturnsEmptyListWithoutError() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        let loaded = try store.load()

        #expect(loaded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path) == false)
    }

    @Test func roundTripWriteAndRead() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        let openedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try store.record(
            rootPath: "/Users/me/Code/dit-giff",
            displayName: "dit-giff",
            openedAt: openedAt
        )

        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].rootPath == "/Users/me/Code/dit-giff")
        #expect(loaded[0].displayName == "dit-giff")
        #expect(loaded[0].lastOpenedAt == openedAt)

        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(raw.contains("\"schemaVersion\" : 1"))
        #expect(raw.contains("dit-giff"))
    }

    @Test func recordingAgainMovesEntryToTopWithoutDuplicating() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        try store.record(rootPath: "/a", displayName: "a", openedAt: Date(timeIntervalSince1970: 1))
        try store.record(rootPath: "/b", displayName: "b", openedAt: Date(timeIntervalSince1970: 2))
        try store.record(rootPath: "/a", displayName: "a-renamed", openedAt: Date(timeIntervalSince1970: 3))

        let loaded = try store.load()
        #expect(loaded.map(\.rootPath) == ["/a", "/b"])
        #expect(loaded[0].displayName == "a-renamed")
        #expect(loaded[0].lastOpenedAt == Date(timeIntervalSince1970: 3))
    }

    @Test func recordingTopEntryAgainDoesNotDuplicate() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        try store.record(rootPath: "/solo", displayName: "solo", openedAt: Date(timeIntervalSince1970: 1))
        try store.record(rootPath: "/solo", displayName: "solo", openedAt: Date(timeIntervalSince1970: 2))

        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].rootPath == "/solo")
        #expect(loaded[0].lastOpenedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func listIsOrderedMostRecentFirst() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        try store.record(rootPath: "/old", displayName: "old", openedAt: Date(timeIntervalSince1970: 10))
        try store.record(rootPath: "/mid", displayName: "mid", openedAt: Date(timeIntervalSince1970: 20))
        try store.record(rootPath: "/new", displayName: "new", openedAt: Date(timeIntervalSince1970: 30))

        #expect(try store.load().map(\.rootPath) == ["/new", "/mid", "/old"])
    }

    @Test func exceedingLimitDropsTheOldest() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        for index in 1...9 {
            try store.record(
                rootPath: "/repo-\(index)",
                displayName: "repo-\(index)",
                openedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let loaded = try store.load()
        #expect(loaded.count == RecentRepositoriesStore.maxEntries)
        #expect(loaded.map(\.rootPath) == (2...9).reversed().map { "/repo-\($0)" })
        #expect(loaded.contains { $0.rootPath == "/repo-1" } == false)
    }

    @Test func removeDropsASpecificEntry() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        try store.record(rootPath: "/keep", displayName: "keep", openedAt: Date(timeIntervalSince1970: 1))
        try store.record(rootPath: "/drop", displayName: "drop", openedAt: Date(timeIntervalSince1970: 2))

        try store.remove(rootPath: "/drop")

        let loaded = try store.load()
        #expect(loaded.map(\.rootPath) == ["/keep"])
    }

    @Test func corruptedFileThrowsNamedError() throws {
        let (store, directory) = try makeStore()
        defer { cleanup(directory) }

        try "not-json-at-all".write(to: store.fileURL, atomically: true, encoding: .utf8)

        let thrown = #expect(throws: RecentRepositoriesStoreError.self) {
            _ = try store.load()
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
          "repositories" : []
        }
        """
        try json.write(to: store.fileURL, atomically: true, encoding: .utf8)

        let thrown = #expect(throws: RecentRepositoriesStoreError.self) {
            _ = try store.load()
        }

        guard case let .corrupted(reason)? = thrown else {
            Issue.record("expected corrupted, got \(String(describing: thrown))")
            return
        }
        #expect(reason.contains("99"))
    }
}
