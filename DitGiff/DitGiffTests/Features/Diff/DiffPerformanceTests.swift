import Testing

@testable import DitGiff

@MainActor
struct DiffPerformanceTests {
    private func makeModel() -> DiffModel {
        DiffModel(replyDelay: ImmediateReplyDelay(), readHunkBaseline: DiffSampleData.readHunkBaseline)
    }

    // MARK: - Line identity

    @Test func lineIdentityIsComposedOfHunkIDAndRowIndex() {
        #expect(DiffLineIdentity.id(hunkID: "h1", rowIndex: 0) == "h1:0")
        #expect(DiffLineIdentity.id(hunkID: "h1", rowIndex: 14) == "h1:14")
        #expect(DiffLineIdentity.id(hunkID: "h2", rowIndex: 0) == "h2:0")
    }

    @Test func lineIdentityDoesNotCollideAcrossHunksAtTheSameOffset() {
        let left = DiffLineIdentity.id(hunkID: "h1", rowIndex: 3)
        let right = DiffLineIdentity.id(hunkID: "h2", rowIndex: 3)
        #expect(left != right)
    }

    @Test func rowIDsCoverEveryLineInOrder() {
        let rows = DiffLineIdentity.rowIDs(hunkID: "h9", lineCount: 4)

        #expect(rows.map(\.id) == ["h9:0", "h9:1", "h9:2", "h9:3"])
        #expect(rows.map(\.rowIndex) == [0, 1, 2, 3])
    }

    // MARK: - Collapse animation limit

    @Test func collapseAnimationUsesTheNamedLineLimit() {
        #expect(DiffCollapseAnimation.maxLineCount == 120)
        #expect(DiffCollapseAnimation.shouldAnimate(lineCount: 0))
        #expect(DiffCollapseAnimation.shouldAnimate(lineCount: DiffCollapseAnimation.maxLineCount))
        #expect(
            DiffCollapseAnimation.shouldAnimate(
                lineCount: DiffCollapseAnimation.maxLineCount + 1
            ) == false
        )
    }

    // MARK: - Line count

    @Test func lineCountSumsEveryHunk() {
        let file = DiffFile(
            path: "Sources/Wide.swift",
            status: .modified,
            additions: 1,
            deletions: 0,
            hunks: [
                DiffHunk(
                    id: "w1",
                    filePath: "Sources/Wide.swift",
                    header: "@@ -1 +1 @@",
                    location: "Wide.swift:1",
                    note: nil,
                    explanation: nil,
                    reply: nil,
                    lines: [
                        DiffLine(
                            oldNumber: 1,
                            newNumber: 1,
                            kind: .context,
                            segments: [DiffLineSegment(text: "abc")]
                        ),
                    ]
                ),
                DiffHunk(
                    id: "w2",
                    filePath: "Sources/Wide.swift",
                    header: "@@ -10 +10 @@",
                    location: "Wide.swift:10",
                    note: nil,
                    explanation: nil,
                    reply: nil,
                    lines: [
                        DiffLine(
                            oldNumber: 10,
                            newNumber: 10,
                            kind: .addition,
                            segments: [DiffLineSegment(text: "abcdefghij")]
                        ),
                    ]
                ),
            ]
        )

        #expect(DiffCodeMetrics.lineCount(in: file) == 2)
    }

    // MARK: - Progress and tree caches

    @Test func readHunkCountStaysConsistentAfterMarkingAHunk() throws {
        let model = makeModel()
        let before = model.readHunkCount
        let billingGuard = try #require(model.hunk(withID: "h1"))

        model.toggleRead(billingGuard)

        #expect(model.readHunkCount == before + 1)
        #expect(model.progressText == "19 of 47 hunks read")
    }

    @Test func fileTreeCacheMatchesAFreshBuildAndSurvivesRepeatedReads() {
        let model = makeModel()
        let first = model.fileTree
        let second = model.fileTree

        #expect(first == second)
        #expect(first == DiffTree.build(files: model.filteredFiles))
    }

    @Test func changingTheFilterRebuildsTheCachedTree() {
        let model = makeModel()
        let unfilteredCount = model.fileTree.count

        model.filter = "InvoiceScheduler.swift"

        #expect(model.filteredFiles.map(\.path) == ["Sources/Billing/InvoiceScheduler.swift"])
        #expect(model.fileTree.count == 1)
        #expect(model.fileTree.count != unfilteredCount)
        #expect(model.fileTree == DiffTree.build(files: model.filteredFiles))
    }

    @Test func clearingTheFilterRestoresTheFullCachedTree() {
        let model = makeModel()
        let fullTree = model.fileTree

        model.filter = "InvoiceScheduler.swift"
        model.filter = ""

        #expect(model.fileTree == fullTree)
        #expect(model.filteredFiles.count == model.files.count)
    }
}

/// Same seam DiffModelTests uses — kept local so this file stays self-contained.
private struct ImmediateReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}
