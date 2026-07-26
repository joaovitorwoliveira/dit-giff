import Foundation

/// Dumb JSON map of reading progress keyed by repository + base/compare refs.
/// Does not talk to git or DiffModel — load and save only.
nonisolated struct ReadingProgressStore: ReadingProgressStoring, Sendable {
    static let currentSchemaVersion = 1
    static let maxEntries = 32
    static let fileName = "reading-progress.json"

    private let directoryURL: URL

    /// - Parameter directoryURL: Directory that will hold `reading-progress.json`.
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

    /// Missing file or missing key → `nil`, not an error.
    func load(key: ReadingProgressKey) throws -> SessionReadingProgress? {
        try loadDocument().entries.first { $0.key == key }?.progress
    }

    /// Inserts or replaces the entry for `key`. Caps at `maxEntries` by dropping the
    /// oldest `updatedAt` values.
    func save(
        key: ReadingProgressKey,
        progress: SessionReadingProgress,
        updatedAt: Date = Date()
    ) throws {
        var entries = try loadDocument().entries
        entries.removeAll { $0.key == key }
        entries.append(
            ReadingProgressEntry(key: key, progress: progress, updatedAt: updatedAt)
        )
        if entries.count > Self.maxEntries {
            entries.sort { $0.updatedAt > $1.updatedAt }
            entries = Array(entries.prefix(Self.maxEntries))
        }
        try saveDocument(
            ReadingProgressDocument(
                schemaVersion: Self.currentSchemaVersion,
                entries: entries
            )
        )
    }

    // MARK: - Persistence

    private func loadDocument() throws -> ReadingProgressDocument {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ReadingProgressDocument(
                schemaVersion: Self.currentSchemaVersion,
                entries: []
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ReadingProgressStoreError.corrupted(reason: error.localizedDescription)
        }

        let document: ReadingProgressDocument
        do {
            document = try Self.makeDecoder().decode(ReadingProgressDocument.self, from: data)
        } catch {
            throw ReadingProgressStoreError.corrupted(reason: error.localizedDescription)
        }

        guard document.schemaVersion == Self.currentSchemaVersion else {
            throw ReadingProgressStoreError.corrupted(
                reason: "unsupported schema version \(document.schemaVersion); expected \(Self.currentSchemaVersion)"
            )
        }

        return document
    }

    private func saveDocument(_ document: ReadingProgressDocument) throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw ReadingProgressStoreError.writeFailed(reason: error.localizedDescription)
        }

        let data: Data
        do {
            data = try Self.makeEncoder().encode(document)
        } catch {
            throw ReadingProgressStoreError.writeFailed(reason: error.localizedDescription)
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
        } catch let error as ReadingProgressStoreError {
            throw error
        } catch {
            throw ReadingProgressStoreError.writeFailed(reason: error.localizedDescription)
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
