import Testing

@testable import DitGiff

struct DiffHunkPatchTests {
    private let multiHunkBody =
        "@@ -1,2 +1,2 @@ first\n"
        + " a\n"
        + "-b\n"
        + "+B\n"
        + "@@ -20,2 +20,3 @@ second\n"
        + " x\n"
        + "+y\n"
        + " z\n"

    // MARK: - Alignment invariant

    /// Every assembled hunk must have a sliced body keyed by the same PatchAdapter id.
    private func assertSlicingAlignsWithParser(patch: Patch) {
        let bodies = DiffHunkPatch.bodies(from: patch)
        var expectedIDs: [String] = []

        for file in patch.files {
            guard let rawBody = file.rawBody else {
                #expect(file.hunks.isEmpty)
                continue
            }

            #expect(
                DiffHunkPatch.hunkSliceCount(in: rawBody) == file.hunks.count,
                "Slice count must match parser hunk count for \(file.path)"
            )

            for index in file.hunks.indices {
                let id = PatchAdapter.hunkID(filePath: file.path, index: index)
                expectedIDs.append(id)

                let sliced = DiffHunkPatch.slice(rawBody: rawBody, hunkIndex: index)
                #expect(sliced != nil)
                #expect(sliced?.hasPrefix(file.hunks[index].header) == true)
                #expect(bodies[id] == sliced)
            }
        }

        #expect(bodies.count == expectedIDs.count)
        #expect(Set(bodies.keys) == Set(expectedIDs))
    }

    @Test func slicingAlignsWithParserOnMultiHunkFile() throws {
        let envelope = PatchFileEnvelope(
            path: "Sources/A.swift",
            oldPath: nil,
            change: .modified,
            body: .text(multiHunkBody),
            oldMode: "100644",
            newMode: "100644",
            rawHeader: "diff --git a/Sources/A.swift b/Sources/A.swift"
        )
        assertSlicingAlignsWithParser(patch: try Patch.assemble(from: [envelope]))
    }

    @Test func slicingAlignsWithParserOnSingleHunkFile() throws {
        let body = "@@ -1 +1 @@\n-old\n+new\n"
        let envelope = PatchFileEnvelope(
            path: "One.swift",
            oldPath: nil,
            change: .modified,
            body: .text(body),
            oldMode: "100644",
            newMode: "100644",
            rawHeader: "diff --git a/One.swift b/One.swift"
        )
        let patch = try Patch.assemble(from: [envelope])
        #expect(patch.files.first?.hunks.count == 1)
        assertSlicingAlignsWithParser(patch: patch)
    }

    @Test func slicingAlignsWhenFileBodyIsEmpty() throws {
        let envelopes = [
            PatchFileEnvelope(
                path: "empty.txt",
                oldPath: nil,
                change: .added,
                body: .noContent,
                oldMode: nil,
                newMode: "100644",
                rawHeader: "diff --git a/empty.txt b/empty.txt"
            ),
            PatchFileEnvelope(
                path: "blank.swift",
                oldPath: nil,
                change: .modified,
                body: .text(""),
                oldMode: "100644",
                newMode: "100644",
                rawHeader: "diff --git a/blank.swift b/blank.swift"
            ),
        ]
        let patch = try Patch.assemble(from: envelopes)
        #expect(patch.files[0].hunks.isEmpty)
        #expect(patch.files[1].hunks.isEmpty)
        assertSlicingAlignsWithParser(patch: patch)
        #expect(DiffHunkPatch.bodies(from: patch).isEmpty)
    }

    @Test func slicingAlignsAcrossMultipleFilesWithDifferentHunkCounts() throws {
        let envelopes = [
            PatchFileEnvelope(
                path: "A.swift",
                oldPath: nil,
                change: .modified,
                body: .text("@@ -1 +1 @@\n-a\n+A\n"),
                oldMode: "100644",
                newMode: "100644",
                rawHeader: "diff --git a/A.swift b/A.swift"
            ),
            PatchFileEnvelope(
                path: "B.swift",
                oldPath: nil,
                change: .modified,
                body: .text(
                    "@@ -1,2 +1,2 @@\n"
                        + " x\n"
                        + "-y\n"
                        + "+Y\n"
                        + "@@ -10,2 +10,2 @@\n"
                        + " p\n"
                        + "-q\n"
                        + "+Q\n"
                ),
                oldMode: "100644",
                newMode: "100644",
                rawHeader: "diff --git a/B.swift b/B.swift"
            ),
            PatchFileEnvelope(
                path: "C.bin",
                oldPath: nil,
                change: .added,
                body: .binary,
                oldMode: nil,
                newMode: "100644",
                rawHeader: "diff --git a/C.bin b/C.bin"
            ),
        ]
        assertSlicingAlignsWithParser(patch: try Patch.assemble(from: envelopes))
    }

    @Test func contentLinesStartingWithAtMarkersStayInsideTheirHunk() throws {
        let body =
            "@@ -1,2 +1,3 @@\n"
            + " @@ still context\n"
            + "+@@ added marker\n"
            + "-old\n"
            + "+new\n"

        let patch = try Patch.assemble(from: [
            PatchFileEnvelope(
                path: "Markers.swift",
                oldPath: nil,
                change: .modified,
                body: .text(body),
                oldMode: "100644",
                newMode: "100644",
                rawHeader: "diff --git a/Markers.swift b/Markers.swift"
            ),
        ])

        #expect(patch.files.first?.hunks.count == 1)
        assertSlicingAlignsWithParser(patch: patch)

        let sliced = try #require(DiffHunkPatch.slice(rawBody: body, hunkIndex: 0))
        #expect(sliced.contains(" @@ still context"))
        #expect(sliced.contains("+@@ added marker"))
        #expect(DiffHunkPatch.hunkSliceCount(in: body) == 1)
    }

    // MARK: - Complementary slice / bodies checks

    @Test func sliceReturnsOneHunkSectionAtATime() {
        let first = DiffHunkPatch.slice(rawBody: multiHunkBody, hunkIndex: 0)
        let second = DiffHunkPatch.slice(rawBody: multiHunkBody, hunkIndex: 1)

        #expect(first?.contains("-b") == true)
        #expect(first?.contains("+B") == true)
        #expect(first?.contains("+y") == false)
        #expect(second?.contains("+y") == true)
        #expect(second?.contains("-b") == false)
    }

    @Test func bodiesMapsHunkIdsFromAPatch() throws {
        let envelope = PatchFileEnvelope(
            path: "Sources/A.swift",
            oldPath: nil,
            change: .modified,
            body: .text(multiHunkBody),
            oldMode: "100644",
            newMode: "100644",
            rawHeader: "diff --git a/Sources/A.swift b/Sources/A.swift"
        )
        let patch = try Patch.assemble(from: [envelope])
        let bodies = DiffHunkPatch.bodies(from: patch)

        let firstID = PatchAdapter.hunkID(filePath: "Sources/A.swift", index: 0)
        let secondID = PatchAdapter.hunkID(filePath: "Sources/A.swift", index: 1)
        #expect(patch.files.first?.hunks.count == 2)
        #expect(bodies[firstID]?.contains("-b") == true)
        #expect(bodies[secondID]?.contains("+y") == true)
        #expect(bodies[firstID]?.contains("+y") == false)
    }

    @Test func outOfRangeIndexReturnsNil() {
        #expect(DiffHunkPatch.slice(rawBody: multiHunkBody, hunkIndex: 2) == nil)
    }
}
