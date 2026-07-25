import Testing

@testable import DitGiff

nonisolated struct PatchAdapterTests {

    // MARK: - Fixtures

    private func hunk(
        header: String = "@@ -1,1 +1,1 @@",
        oldStart: Int = 1,
        oldCount: Int = 1,
        newStart: Int = 1,
        newCount: Int = 1,
        lines: [PatchLine]
    ) -> PatchHunk {
        PatchHunk(
            header: header,
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            lines: lines
        )
    }

    private func line(
        old: Int?,
        new: Int?,
        kind: PatchLineKind,
        text: String,
        highlighted: Bool = false
    ) -> PatchLine {
        PatchLine(
            oldNumber: old,
            newNumber: new,
            kind: kind,
            segments: [PatchLineSegment(text: text, isHighlighted: highlighted)]
        )
    }

    private func file(
        path: String,
        change: PatchFileChange,
        hunks: [PatchHunk] = [],
        isBinary: Bool = false,
        isSubmodule: Bool = false,
        additions: Int = 0,
        deletions: Int = 0,
        oldPath: String? = nil
    ) -> PatchFile {
        PatchFile(
            path: path,
            oldPath: oldPath,
            change: change,
            hunks: hunks,
            isBinary: isBinary,
            isSubmodule: isSubmodule,
            additions: additions,
            deletions: deletions
        )
    }

    // MARK: - Modified with several hunks

    @Test func adaptsModifiedFileWithSeveralHunks() {
        let patch = Patch(files: [
            file(
                path: "Sources/Billing/BillingGuard.swift",
                change: .modified,
                hunks: [
                    hunk(
                        header: "@@ -10,3 +10,3 @@ first",
                        oldStart: 10,
                        oldCount: 3,
                        newStart: 10,
                        newCount: 3,
                        lines: [
                            line(old: 10, new: 10, kind: .context, text: "keep"),
                            line(old: 11, new: nil, kind: .deletion, text: "old", highlighted: true),
                            line(old: nil, new: 11, kind: .addition, text: "new", highlighted: true),
                        ]
                    ),
                    hunk(
                        header: "@@ -40,2 +40,2 @@ second",
                        oldStart: 40,
                        oldCount: 2,
                        newStart: 40,
                        newCount: 2,
                        lines: [
                            line(old: 40, new: 40, kind: .context, text: "a"),
                            line(old: 41, new: nil, kind: .deletion, text: "b"),
                            line(old: nil, new: 41, kind: .addition, text: "B"),
                        ]
                    ),
                ],
                additions: 2,
                deletions: 2
            ),
        ])

        let files = PatchAdapter.toDiffFiles(patch)
        #expect(files.count == 1)
        let diffFile = files[0]
        #expect(diffFile.path == "Sources/Billing/BillingGuard.swift")
        #expect(diffFile.status == .modified)
        #expect(diffFile.hunks.count == 2)

        #expect(diffFile.hunks[0].id == "Sources/Billing/BillingGuard.swift#0")
        #expect(diffFile.hunks[0].header == "@@ -10,3 +10,3 @@ first")
        #expect(diffFile.hunks[0].location == "BillingGuard.swift:10")
        #expect(diffFile.hunks[0].filePath == "Sources/Billing/BillingGuard.swift")
        #expect(diffFile.hunks[0].note == nil)
        #expect(diffFile.hunks[0].explanation == nil)
        #expect(diffFile.hunks[0].reply == nil)
        #expect(diffFile.hunks[0].lines.count == 3)
        #expect(diffFile.hunks[0].lines[1].kind == .deletion)
        #expect(diffFile.hunks[0].lines[1].segments[0].isHighlighted)
        #expect(diffFile.hunks[0].lines[2].kind == .addition)

        #expect(diffFile.hunks[1].id == "Sources/Billing/BillingGuard.swift#1")
        #expect(diffFile.hunks[1].location == "BillingGuard.swift:40")
    }

    // MARK: - Status mapping

    @Test func adaptsAddedFile() {
        let patch = Patch(files: [
            file(
                path: "New.swift",
                change: .added,
                hunks: [
                    hunk(
                        header: "@@ -0,0 +1,1 @@",
                        oldStart: 0,
                        oldCount: 0,
                        newStart: 1,
                        newCount: 1,
                        lines: [line(old: nil, new: 1, kind: .addition, text: "hi")]
                    ),
                ],
                additions: 1
            ),
        ])

        let diffFile = PatchAdapter.toDiffFiles(patch)[0]
        #expect(diffFile.status == .added)
        #expect(diffFile.hunks[0].location == "New.swift:1")
    }

    @Test func adaptsDeletedFileLocationUsesOldSide() {
        let patch = Patch(files: [
            file(
                path: "Gone.swift",
                change: .deleted,
                hunks: [
                    hunk(
                        header: "@@ -12,2 +0,0 @@",
                        oldStart: 12,
                        oldCount: 2,
                        newStart: 0,
                        newCount: 0,
                        lines: [
                            line(old: 12, new: nil, kind: .deletion, text: "a"),
                            line(old: 13, new: nil, kind: .deletion, text: "b"),
                        ]
                    ),
                ],
                deletions: 2
            ),
        ])

        let diffFile = PatchAdapter.toDiffFiles(patch)[0]
        #expect(diffFile.status == .deleted)
        #expect(diffFile.hunks.count == 1)
        #expect(diffFile.hunks[0].location == "Gone.swift:12")
        #expect(diffFile.hunks[0].id == "Gone.swift#0")
    }

    @Test func adaptsRenamedFile() {
        let patch = Patch(files: [
            file(
                path: "Sources/HTTP/AvatarLoader.swift",
                change: .renamed(from: "Sources/HTTP/OldAvatar.swift"),
                hunks: [
                    hunk(
                        header: "@@ -1,1 +1,1 @@",
                        lines: [
                            line(old: 1, new: nil, kind: .deletion, text: "x"),
                            line(old: nil, new: 1, kind: .addition, text: "y"),
                        ]
                    ),
                ],
                additions: 1,
                deletions: 1,
                oldPath: "Sources/HTTP/OldAvatar.swift"
            ),
        ])

        let diffFile = PatchAdapter.toDiffFiles(patch)[0]
        #expect(diffFile.status == .renamed)
        #expect(diffFile.path == "Sources/HTTP/AvatarLoader.swift")
        #expect(diffFile.hunks[0].location == "AvatarLoader.swift:1")
    }

    @Test func mapsCopiedToAdded() {
        let patch = Patch(files: [
            file(
                path: "Copy.swift",
                change: .copied(from: "Original.swift"),
                hunks: [
                    hunk(
                        header: "@@ -0,0 +1,1 @@",
                        oldStart: 0,
                        oldCount: 0,
                        newStart: 1,
                        newCount: 1,
                        lines: [line(old: nil, new: 1, kind: .addition, text: "c")]
                    ),
                ],
                additions: 1,
                oldPath: "Original.swift"
            ),
        ])

        let diffFile = PatchAdapter.toDiffFiles(patch)[0]
        #expect(diffFile.status == .added)
    }

    // MARK: - Empty-hunk kinds

    @Test func binarySubmoduleAndNoContentBecomeFilesWithEmptyHunks() {
        let patch = Patch(files: [
            file(path: "a.bin", change: .added, isBinary: true),
            file(path: "vendor", change: .modified, isSubmodule: true),
            file(path: "empty.txt", change: .added),
        ])

        let files = PatchAdapter.toDiffFiles(patch)
        #expect(files.map(\.path) == ["a.bin", "vendor", "empty.txt"])
        #expect(files.allSatisfy { $0.hunks.isEmpty })
        #expect(files.allSatisfy { $0.additions == 0 && $0.deletions == 0 })

        // DiffTree.build only walks paths — empty hunk lists must not crash it.
        let tree = DiffTree.build(files: files)
        #expect(tree.count == 3)
    }

    // MARK: - Counts

    @Test func passesThroughAdditionAndDeletionCounts() {
        let patch = Patch(files: [
            file(
                path: "Counted.swift",
                change: .modified,
                hunks: [
                    hunk(
                        lines: [
                            line(old: 1, new: nil, kind: .deletion, text: "a"),
                            line(old: nil, new: 1, kind: .addition, text: "b"),
                            line(old: nil, new: 2, kind: .addition, text: "c"),
                        ]
                    ),
                ],
                additions: 99,
                deletions: 42
            ),
        ])

        let diffFile = PatchAdapter.toDiffFiles(patch)[0]
        #expect(diffFile.additions == 99)
        #expect(diffFile.deletions == 42)
    }

    // MARK: - ID stability and uniqueness

    @Test func hunkIDsAreStableAcrossTwoAdaptationsOfTheSamePatch() {
        let patch = Patch(files: [
            file(
                path: "A.swift",
                change: .modified,
                hunks: [
                    hunk(newStart: 5, lines: [line(old: 5, new: 5, kind: .context, text: "x")]),
                    hunk(newStart: 20, lines: [line(old: 20, new: 20, kind: .context, text: "y")]),
                ],
                additions: 0,
                deletions: 0
            ),
        ])

        let first = PatchAdapter.toDiffFiles(patch).flatMap(\.hunks).map(\.id)
        let second = PatchAdapter.toDiffFiles(patch).flatMap(\.hunks).map(\.id)
        #expect(first == second)
        #expect(first == ["A.swift#0", "A.swift#1"])
    }

    @Test func hunkIDsDifferAcrossFilesEvenWithTheSameNewStart() {
        let sharedHunk = hunk(
            header: "@@ -7,1 +7,1 @@",
            oldStart: 7,
            oldCount: 1,
            newStart: 7,
            newCount: 1,
            lines: [line(old: 7, new: 7, kind: .context, text: "same")]
        )
        let patch = Patch(files: [
            file(path: "One.swift", change: .modified, hunks: [sharedHunk]),
            file(path: "Two.swift", change: .modified, hunks: [sharedHunk]),
        ])

        let ids = PatchAdapter.toDiffFiles(patch).flatMap(\.hunks).map(\.id)
        #expect(ids == ["One.swift#0", "Two.swift#0"])
        #expect(Set(ids).count == 2)
    }
}
