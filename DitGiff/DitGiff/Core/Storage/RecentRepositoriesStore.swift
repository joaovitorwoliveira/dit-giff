import Foundation

/// Dumb JSON list of recently opened repositories. Does not check that paths still exist.
nonisolated struct RecentRepositoriesStore: Sendable {
    static let currentSchemaVersion = 1
    static let maxEntries = 8
    static let fileName = "recent-repositories.json"

    private let directoryURL: URL

    /// - Parameter directoryURL: Directory that will hold `recent-repositories.json`.
    ///   Defaults to `Application Support/DitGiff`, created if needed.
    init(directoryURL: URL? = nil) throws {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directoryURL = support.appendingPathComponent("DitGiff", isDirectory: true)
        }
    }

    var fileURL: URL {
        directoryURL.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    /// Most recent first. Missing file → empty list, not an error.
    func load() throws -> [RecentRepository] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw RecentRepositoriesStoreError.corrupted(reason: error.localizedDescription)
        }

        let document: RecentRepositoriesDocument
        do {
            document = try Self.makeDecoder().decode(RecentRepositoriesDocument.self, from: data)
        } catch {
            throw RecentRepositoriesStoreError.corrupted(reason: error.localizedDescription)
        }

        guard document.schemaVersion == Self.currentSchemaVersion else {
            throw RecentRepositoriesStoreError.corrupted(
                reason: "unsupported schema version \(document.schemaVersion); expected \(Self.currentSchemaVersion)"
            )
        }

        return document.repositories
    }

    /// Inserts or refreshes an entry at the top. Dedupes by `rootPath`. Caps at `maxEntries`.
    func record(rootPath: String, displayName: String, openedAt: Date = Date()) throws {
        var repositories = try load()
        repositories.removeAll { $0.rootPath == rootPath }
        repositories.insert(
            RecentRepository(rootPath: rootPath, displayName: displayName, lastOpenedAt: openedAt),
            at: 0
        )
        if repositories.count > Self.maxEntries {
            repositories = Array(repositories.prefix(Self.maxEntries))
        }
        try save(repositories)
    }

    func remove(rootPath: String) throws {
        var repositories = try load()
        repositories.removeAll { $0.rootPath == rootPath }
        try save(repositories)
    }

    // MARK: - Persistence

    private func save(_ repositories: [RecentRepository]) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw RecentRepositoriesStoreError.writeFailed(reason: error.localizedDescription)
        }

        let document = RecentRepositoriesDocument(
            schemaVersion: Self.currentSchemaVersion,
            repositories: repositories
        )

        let data: Data
        do {
            data = try Self.makeEncoder().encode(document)
        } catch {
            throw RecentRepositoriesStoreError.writeFailed(reason: error.localizedDescription)
        }

        // Atomic write: temp file beside the destination, then replace/rename.
        let temporaryURL = directoryURL.appendingPathComponent(
            "\(Self.fileName).tmp",
            isDirectory: false
        )
        do {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try fileManager.removeItem(at: temporaryURL)
            }
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: fileURL)
            }
        } catch let error as RecentRepositoriesStoreError {
            throw error
        } catch {
            throw RecentRepositoriesStoreError.writeFailed(reason: error.localizedDescription)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
