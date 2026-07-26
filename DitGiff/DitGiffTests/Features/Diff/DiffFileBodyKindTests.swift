import Testing

@testable import DitGiff

nonisolated struct DiffFileBodyKindTests {
    @Test func readerSummariesDescribeWithoutVerdict() {
        #expect(DiffFileBodyKind.binary.readerSummary == "Binary file. No text to show.")
        #expect(DiffFileBodyKind.submodule(oldSHA: nil, newSHA: nil).readerSummary
            == "Submodule pointer changed.")
        #expect(DiffFileBodyKind.noContent.readerSummary == "No content in this patch.")
    }

    @Test func submoduleDetailShowsBothSHAsWhenPresent() {
        let body = DiffFileBodyKind.submodule(oldSHA: "oldsha", newSHA: "newsha")
        #expect(body.readerDetail == "oldsha → newsha")
    }

    @Test func submoduleDetailFallsBackToASingleSide() {
        #expect(
            DiffFileBodyKind.submodule(oldSHA: nil, newSHA: "only-new").readerDetail
                == "only-new"
        )
        #expect(
            DiffFileBodyKind.submodule(oldSHA: "only-old", newSHA: nil).readerDetail
                == "only-old"
        )
        #expect(DiffFileBodyKind.submodule(oldSHA: nil, newSHA: nil).readerDetail == nil)
    }

    @Test func belongsInReaderIncludesSpecialBodiesAndTextWithHunks() {
        let hunk = DiffHunk(
            id: "a#0",
            filePath: "a.swift",
            header: "@@ -1 +1 @@",
            location: "a.swift:1",
            note: nil,
            explanation: nil,
            reply: nil,
            lines: [
                DiffLine(
                    oldNumber: 1,
                    newNumber: 1,
                    kind: .context,
                    segments: [DiffLineSegment(text: "x")]
                ),
            ]
        )
        #expect(
            DiffFile(
                path: "a.swift",
                status: .modified,
                additions: 0,
                deletions: 0,
                hunks: [hunk],
                body: .text
            ).belongsInReader
        )
        #expect(
            DiffFile(
                path: "b.bin",
                status: .modified,
                additions: 0,
                deletions: 0,
                hunks: [],
                body: .binary
            ).belongsInReader
        )
        #expect(
            DiffFile(
                path: "vendor",
                status: .modified,
                additions: 0,
                deletions: 0,
                hunks: [],
                body: .submodule(oldSHA: nil, newSHA: "abc")
            ).belongsInReader
        )
        #expect(
            DiffFile(
                path: "empty.txt",
                status: .added,
                additions: 0,
                deletions: 0,
                hunks: [],
                body: .noContent
            ).belongsInReader
        )
        #expect(
            DiffFile(
                path: "broken.swift",
                status: .modified,
                additions: 0,
                deletions: 0,
                hunks: [],
                body: .text
            ).belongsInReader == false
        )
    }
}
