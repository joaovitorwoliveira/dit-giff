import Foundation

extension DiffModel {
    // MARK: - Reading progress persistence

    /// Snapshot + write. Synchronous on purpose: human-speed actions, small JSON, and a
    /// debounce would lose progress if the process dies between the action and the flush.
    func persistReadingProgress() {
        guard !usesSampleData else { return }
        guard let store = readingProgressStore, let key = progressKey else { return }

        progressPersistCount += 1
        let progress = makeSessionReadingProgress()
        do {
            try store.save(key: key, progress: progress)
            readingProgressError = nil
        } catch {
            readingProgressError = Self.presentableProgressMessage(for: error)
        }
    }

    /// Load → reconcile → apply. Runs after `apply(patch:)` so fingerprints see
    /// `filePatchBodies`. A store failure starts clean rather than blocking the diff.
    func restoreReadingProgress() {
        guard !usesSampleData else { return }
        guard let store = readingProgressStore, let key = progressKey else { return }

        let saved: SessionReadingProgress?
        do {
            saved = try store.load(key: key)
        } catch {
            // Prefer a clean session over claiming reads we cannot verify.
            return
        }
        guard let saved else { return }

        let reconciled = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: currentReadingFingerprints()
        )
        applyRestoredProgress(reconciled)
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

        guard let path = progress.focusedFilePath, let file = file(atPath: path) else {
            return
        }
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

    /// Text files hash the raw patch body. Binary / submodule / no-content hash a
    /// deterministic descriptor from what the assembled patch still carries — see
    /// `nonTextReadingDescriptor`. Empty string is never used as a shared stand-in.
    func readingFingerprint(for file: DiffFile) -> String {
        if let rawBody = filePatchBodies[file.path] {
            return readingProgressFingerprint(for: rawBody)
        }
        return readingProgressFingerprint(for: nonTextReadingDescriptor(for: file))
    }

    /// PatchEnvelope does not keep the `index abc..def` blob line for binaries, so a
    /// binary content change is invisible here. Submodule SHAs are included when git
    /// printed `Subproject commit` lines.
    private func nonTextReadingDescriptor(for file: DiffFile) -> String {
        let statusToken: String
        switch file.status {
        case .added: statusToken = "added"
        case .deleted: statusToken = "deleted"
        case .modified: statusToken = "modified"
        case .renamed: statusToken = "renamed"
        }

        switch file.body {
        case .text:
            // Text without a raw body should not happen; still avoid colliding with binary.
            return "text|\(statusToken)|\(file.path)"
        case .binary:
            return "binary|\(statusToken)|\(file.path)"
        case let .submodule(oldSHA, newSHA):
            let old = oldSHA ?? ""
            let new = newSHA ?? ""
            return "submodule|\(statusToken)|\(file.path)|\(old)|\(new)"
        case .noContent:
            return "noContent|\(statusToken)|\(file.path)"
        }
    }

    private static func presentableProgressMessage(for error: Error) -> String {
        if let storeError = error as? ReadingProgressStoreError {
            return storeError.errorDescription ?? String(describing: storeError)
        }
        return error.localizedDescription
    }
}
