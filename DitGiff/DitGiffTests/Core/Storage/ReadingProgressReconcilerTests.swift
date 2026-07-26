import Foundation
import Testing

@testable import DitGiff

nonisolated struct ReadingProgressReconcilerTests {

    private func file(
        path: String,
        fingerprint: String,
        isViewed: Bool = true,
        readHunkIDs: [String] = ["h1"],
        isCollapsed: Bool = true
    ) -> FileReadingProgress {
        FileReadingProgress(
            path: path,
            patchFingerprint: fingerprint,
            isViewed: isViewed,
            readHunkIDs: readHunkIDs,
            isCollapsed: isCollapsed
        )
    }

    @Test func matchingFingerprintKeepsFileProgress() {
        let saved = SessionReadingProgress(
            files: [file(path: "a.swift", fingerprint: "fp-a")],
            closedDirectories: [],
            focusedFilePath: "a.swift"
        )

        let result = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: ["a.swift": "fp-a"]
        )

        #expect(result.files == saved.files)
        #expect(result.focusedFilePath == "a.swift")
    }

    @Test func changedFingerprintDropsFileProgress() {
        let saved = SessionReadingProgress(
            files: [
                file(path: "a.swift", fingerprint: "old"),
                file(path: "b.swift", fingerprint: "same")
            ],
            closedDirectories: [],
            focusedFilePath: nil
        )

        let result = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: [
                "a.swift": "new",
                "b.swift": "same"
            ]
        )

        #expect(result.files.map(\.path) == ["b.swift"])
        #expect(result.files[0].patchFingerprint == "same")
    }

    @Test func missingFileIsRemoved() {
        let saved = SessionReadingProgress(
            files: [
                file(path: "gone.swift", fingerprint: "fp"),
                file(path: "stay.swift", fingerprint: "fp")
            ],
            closedDirectories: [],
            focusedFilePath: nil
        )

        let result = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: ["stay.swift": "fp"]
        )

        #expect(result.files.map(\.path) == ["stay.swift"])
    }

    @Test func invalidFocusedPathBecomesNil() {
        let saved = SessionReadingProgress(
            files: [file(path: "a.swift", fingerprint: "fp")],
            closedDirectories: [],
            focusedFilePath: "gone.swift"
        )

        let result = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: ["a.swift": "fp"]
        )

        #expect(result.focusedFilePath == nil)
    }

    @Test func closedDirectoriesSurviveWithoutFingerprintCheck() {
        let saved = SessionReadingProgress(
            files: [file(path: "a.swift", fingerprint: "old")],
            closedDirectories: ["src", "src/billing"],
            focusedFilePath: "a.swift"
        )

        let result = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: ["a.swift": "new"]
        )

        #expect(result.files.isEmpty)
        #expect(result.closedDirectories == ["src", "src/billing"])
        #expect(result.focusedFilePath == "a.swift")
    }

    @Test func newFilesInCurrentDiffHaveNoProgress() {
        let saved = SessionReadingProgress(
            files: [file(path: "old.swift", fingerprint: "fp")],
            closedDirectories: [],
            focusedFilePath: nil
        )

        let result = reconcileReadingProgress(
            saved: saved,
            currentFingerprints: [
                "old.swift": "fp",
                "brand-new.swift": "whatever"
            ]
        )

        #expect(result.files.map(\.path) == ["old.swift"])
    }
}
