import Foundation

extension DiffModel {
    // MARK: - Reading progress persistence

    /// Snapshot + write. Synchronous on purpose: human-speed actions, small JSON, and a
    /// debounce would lose progress if the process dies between the action and the flush.
    func persistReadingProgress() {
        guard !usesSampleData else { return }
        guard let store = readingProgressStore, let key = progressKey else { return }

        let progress = makeSessionReadingProgress()
        do {
            try store.save(key: key, progress: progress)
            readingProgressError = nil
        } catch {
            readingProgressError = Self.presentableProgressMessage(for: error)
        }
    }

    /// Load → reconcile → apply. Runs after `apply(patch:)` so fingerprints see
    /// `filePatchBodies` / `filePatchHeaders`. A store failure starts clean and
    /// surfaces `readingProgressError` so the reader is not left guessing.
    func restoreReadingProgress() {
        guard !usesSampleData else { return }
        guard let store = readingProgressStore, let key = progressKey else { return }

        let saved: SessionReadingProgress?
        do {
            saved = try store.load(key: key)
        } catch {
            // Prefer a clean session over claiming reads we cannot verify — but say so.
            readingProgressError = Self.unreadableProgressMessage(
                detail: Self.presentableProgressMessage(for: error)
            )
            return
        }
        guard let saved else { return }

        let reconciled = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: currentReadingFingerprints()
        )
        applyRestoredProgress(reconciled)
    }

    /// Lets the view dismiss a surfaced progress error after the reader has seen it.
    func clearReadingProgressError() {
        readingProgressError = nil
    }

    // MARK: - Snapshot / restore

    private func makeSessionReadingProgress() -> SessionReadingProgress {
        let paths = pathsWithReadingMarks()
        let filesProgress: [FileReadingProgress] = paths.compactMap { path in
            guard let file = file(atPath: path) else { return nil }
            let hunkIDs = readHunkIDs
                .filter { hunkID in
                    hunk(withID: hunkID)?.filePath == path
                }
                .sorted()
            return FileReadingProgress(
                path: path,
                patchFingerprint: readingFingerprint(for: file),
                isViewed: viewedPaths.contains(path),
                readHunkIDs: hunkIDs,
                isCollapsed: collapsedPaths.contains(path)
            )
        }

        return SessionReadingProgress(
            files: filesProgress,
            closedDirectories: closedDirectories.sorted(),
            focusedFilePath: focusedFilePath
        )
    }

    private func applyRestoredProgress(_ progress: SessionReadingProgress) {
        var viewed: Set<String> = []
        var collapsed: Set<String> = []
        var hunkIDs: Set<String> = []

        for file in progress.files {
            if file.isViewed {
                viewed.insert(file.path)
            }
            if file.isCollapsed {
                collapsed.insert(file.path)
            }
            hunkIDs.formUnion(file.readHunkIDs)
        }

        viewedPaths = viewed
        collapsedPaths = collapsed
        readHunkIDs = hunkIDs
        closedDirectories = Set(progress.closedDirectories)
        focusedFilePath = progress.focusedFilePath
        refreshViewedDirectoryStates()
        refreshReadProgress()

        guard let path = progress.focusedFilePath else { return }
        // Directory focus does not survive fingerprint reconcile today; if it did,
        // restore focus without scrolling the reader.
        if DiffTreeLinePath.isDirectory(path) {
            focusedFilePath = path
            return
        }
        guard let file = file(atPath: path) else { return }
        // Restore is an explicit "put me back" — open closed ancestors so the row exists.
        ensureAncestorDirectoriesOpen(forFilePath: path)
        revealFileInReader(file)
    }

    private func pathsWithReadingMarks() -> [String] {
        var paths = viewedPaths.union(collapsedPaths)
        for hunkID in readHunkIDs {
            guard let hunk = hunk(withID: hunkID) else { continue }
            paths.insert(hunk.filePath)
        }
        return paths.sorted()
    }

    // MARK: - Fingerprints

    /// Path → fingerprint for every file in the current diff. Used by reconciliation.
    private func currentReadingFingerprints() -> [String: String] {
        var fingerprints: [String: String] = [:]
        fingerprints.reserveCapacity(files.count)
        for file in files {
            fingerprints[file.path] = readingFingerprint(for: file)
        }
        return fingerprints
    }

    /// Text files hash the raw patch body. Non-text files hash the raw header git
    /// printed for that section (`index` blob lines, modes, Subproject commit) —
    /// never a synthesized status|path descriptor, which misses content changes.
    func readingFingerprint(for file: DiffFile) -> String {
        if let rawBody = filePatchBodies[file.path] {
            return readingProgressFingerprint(for: rawBody)
        }
        if let header = filePatchHeaders[file.path] {
            return readingProgressFingerprint(for: header)
        }
        // Loaded files always carry a body or a header from assemble. Path-keyed
        // fallback avoids colliding unrelated missing entries onto one digest.
        return readingProgressFingerprint(for: "missing-fingerprint|\(file.path)")
    }

    private static let unreadableProgressPrefix =
        "Saved reading progress could not be read. Starting this review clean."

    private static func unreadableProgressMessage(detail: String) -> String {
        "\(unreadableProgressPrefix) \(detail)"
    }

    private static func presentableProgressMessage(for error: Error) -> String {
        if let storeError = error as? ReadingProgressStoreError {
            return storeError.errorDescription ?? String(describing: storeError)
        }
        return error.localizedDescription
    }
}
