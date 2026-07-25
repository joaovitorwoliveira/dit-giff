import Testing

@testable import DitGiff

nonisolated struct HunkParserTests {

    // MARK: - Simple hunk

    @Test func parsesSimpleHunkWithContextAdditionAndDeletion() throws {
        let body = """
        @@ -10,3 +10,3 @@ func greet()
         keep
        -old
        +new
         tail
        """

        let hunks = try HunkParser.parse(body)
        #expect(hunks.count == 1)

        let hunk = try #require(hunks.first)
        #expect(hunk.header == "@@ -10,3 +10,3 @@ func greet()")
        #expect(hunk.oldStart == 10)
        #expect(hunk.oldCount == 3)
        #expect(hunk.newStart == 10)
        #expect(hunk.newCount == 3)
        #expect(hunk.lines.count == 4)

        #expect(hunk.lines[0].kind == .context)
        #expect(hunk.lines[0].oldNumber == 10)
        #expect(hunk.lines[0].newNumber == 10)
        #expect(hunk.lines[0].text == "keep")

        #expect(hunk.lines[1].kind == .deletion)
        #expect(hunk.lines[1].oldNumber == 11)
        #expect(hunk.lines[1].newNumber == nil)
        #expect(hunk.lines[1].text == "old")

        #expect(hunk.lines[2].kind == .addition)
        #expect(hunk.lines[2].oldNumber == nil)
        #expect(hunk.lines[2].newNumber == 11)
        #expect(hunk.lines[2].text == "new")

        #expect(hunk.lines[3].kind == .context)
        #expect(hunk.lines[3].oldNumber == 12)
        #expect(hunk.lines[3].newNumber == 12)
        #expect(hunk.lines[3].text == "tail")
    }

    // MARK: - Multiple hunks

    @Test func parsesMultipleHunksInSameBody() throws {
        let body = """
        @@ -1,2 +1,2 @@ first
         a
        -b
        +B
        @@ -20,2 +20,3 @@ second
         x
        +y
         z
        """

        let hunks = try HunkParser.parse(body)
        #expect(hunks.count == 2)
        #expect(hunks[0].header == "@@ -1,2 +1,2 @@ first")
        #expect(hunks[0].lines.count == 3)
        #expect(hunks[1].header == "@@ -20,2 +20,3 @@ second")
        #expect(hunks[1].oldCount == 2)
        #expect(hunks[1].newCount == 3)
        #expect(hunks[1].lines.map(\.kind) == [.context, .addition, .context])
        #expect(hunks[1].lines[1].newNumber == 21)
        #expect(hunks[1].lines[2].oldNumber == 21)
        #expect(hunks[1].lines[2].newNumber == 22)
    }

    // MARK: - Header shapes

    @Test func headerWithoutCommaMeansCountOne() throws {
        let body = """
        @@ -5 +5 @@
        -solo
        +only
        """

        let hunks = try HunkParser.parse(body)
        let hunk = try #require(hunks.first)
        #expect(hunk.oldStart == 5)
        #expect(hunk.oldCount == 1)
        #expect(hunk.newStart == 5)
        #expect(hunk.newCount == 1)
        #expect(hunk.header == "@@ -5 +5 @@")
        #expect(hunk.lines.count == 2)
    }

    @Test func headerWithCommaOnOneSideOnly() throws {
        let body = """
        @@ -5,3 +10 @@
         a
        -b
        -c
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.oldStart == 5)
        #expect(hunk.oldCount == 3)
        #expect(hunk.newStart == 10)
        #expect(hunk.newCount == 1)
        #expect(hunk.header == "@@ -5,3 +10 @@")
        #expect(hunk.lines.map(\.kind) == [.context, .deletion, .deletion])
        #expect(hunk.lines.map(\.newNumber) == [10, nil, nil])
    }

    @Test func preservesTrailingContextAfterSecondAtMarkers() throws {
        let body = """
        @@ -2,1 +2,1 @@ class Widget
        -alpha
        +beta
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.header == "@@ -2,1 +2,1 @@ class Widget")
    }

    @Test func zeroZeroHeaderProducesEmptyHunk() throws {
        let body = "@@ -1,0 +1,0 @@\n"
        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.oldStart == 1)
        #expect(hunk.oldCount == 0)
        #expect(hunk.newStart == 1)
        #expect(hunk.newCount == 0)
        #expect(hunk.lines.isEmpty)
    }

    // MARK: - Additions only / deletions only

    @Test func parsesAdditionsOnlyFile() throws {
        let body = """
        @@ -0,0 +1,3 @@
        +one
        +two
        +three
        """

        let hunks = try HunkParser.parse(body)
        let hunk = try #require(hunks.first)
        #expect(hunk.oldStart == 0)
        #expect(hunk.oldCount == 0)
        #expect(hunk.newStart == 1)
        #expect(hunk.newCount == 3)
        #expect(hunk.lines.map(\.kind) == [.addition, .addition, .addition])
        #expect(hunk.lines.map(\.oldNumber) == [nil, nil, nil])
        #expect(hunk.lines.map(\.newNumber) == [1, 2, 3])
        #expect(hunk.lines.allSatisfy { line in
            line.segments.count == 1 && line.segments[0].isHighlighted == false
        })
    }

    @Test func parsesDeletionsOnlyFile() throws {
        let body = """
        @@ -1,3 +0,0 @@
        -one
        -two
        -three
        """

        let hunks = try HunkParser.parse(body)
        let hunk = try #require(hunks.first)
        #expect(hunk.oldCount == 3)
        #expect(hunk.newCount == 0)
        #expect(hunk.lines.map(\.kind) == [.deletion, .deletion, .deletion])
        #expect(hunk.lines.map(\.oldNumber) == [1, 2, 3])
        #expect(hunk.lines.map(\.newNumber) == [nil, nil, nil])
    }

    @Test func emptyAdditionLineIsAdditionWithEmptyText() throws {
        let body = """
        @@ -1,1 +1,2 @@
         keep
        +
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.lines.count == 2)
        #expect(hunk.lines[1].kind == .addition)
        #expect(hunk.lines[1].text == "")
        #expect(hunk.lines[1].newNumber == 2)
    }

    // MARK: - Empty context / empty body

    @Test func emptyContextLineIsContextNotEndOfHunk() throws {
        let body = "@@ -1,3 +1,3 @@\n keep\n\n-tail\n+Tail\n"

        let hunks = try HunkParser.parse(body)
        let hunk = try #require(hunks.first)
        #expect(hunk.lines.count == 4)
        #expect(hunk.lines[1].kind == .context)
        #expect(hunk.lines[1].text == "")
        #expect(hunk.lines[1].oldNumber == 2)
        #expect(hunk.lines[1].newNumber == 2)
        #expect(hunk.lines[2].kind == .deletion)
        #expect(hunk.lines[3].kind == .addition)
    }

    @Test func emptyBodyReturnsEmptyList() throws {
        let hunks = try HunkParser.parse("")
        #expect(hunks.isEmpty)
    }

    // MARK: - No newline at end of file

    @Test func noNewlineMarkerIsNotAPatchLine() throws {
        let body = """
        @@ -1,2 +1,2 @@
         keep
        -old
        +new
        \\ No newline at end of file
        """

        let hunks = try HunkParser.parse(body)
        let hunk = try #require(hunks.first)
        #expect(hunk.oldCount == 2)
        #expect(hunk.newCount == 2)
        #expect(hunk.lines.count == 3)
        #expect(hunk.lines.map(\.text) == ["keep", "old", "new"])
        #expect(hunk.lines.allSatisfy { !$0.text.contains("No newline") })
    }

    @Test func noNewlineMarkerBetweenDeletionAndAddition() throws {
        let body = """
        @@ -1,1 +1,1 @@
        -old
        \\ No newline at end of file
        +new
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.lines.count == 2)
        #expect(hunk.lines.map(\.kind) == [.deletion, .addition])
        #expect(hunk.lines[0].text == "old")
        #expect(hunk.lines[1].text == "new")
        #expect(hunk.lines[0].segments == [
            PatchLineSegment(text: "old", isHighlighted: true),
        ])
        #expect(hunk.lines[1].segments == [
            PatchLineSegment(text: "new", isHighlighted: true),
        ])
    }

    @Test func twoNoNewlineMarkersInSameHunk() throws {
        let body = """
        @@ -1,1 +1,1 @@
        -old
        \\ No newline at end of file
        +new
        \\ No newline at end of file
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.oldCount == 1)
        #expect(hunk.newCount == 1)
        #expect(hunk.lines.count == 2)
        #expect(hunk.lines.map(\.text) == ["old", "new"])
    }

    @Test func unrecognizedBackslashLineThrows() {
        let body = """
        @@ -1,1 +1,1 @@
        -old
        \\ not the real marker
        +new
        """

        do {
            _ = try HunkParser.parse(body)
            Issue.record("Expected unexpectedLine")
        } catch let error as HunkParserError {
            guard case let .unexpectedLine(line) = error else {
                Issue.record("Wrong error case: \(error)")
                return
            }
            #expect(line == "\\ not the real marker")
            #expect(error.errorDescription != nil)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Content that looks like diff headers

    @Test func addedLinesThatLookLikeDiffHeadersStayContent() throws {
        // Raw lines carry one leading "+" marker; the rest is content, including
        // text that itself looks like a diff header.
        let body = """
        @@ -0,0 +1,2 @@
        ++++ b/arquivo
        +diff --git a/x b/x
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.lines.count == 2)
        #expect(hunk.lines[0].kind == .addition)
        #expect(hunk.lines[0].text == "+++ b/arquivo")
        #expect(hunk.lines[1].kind == .addition)
        #expect(hunk.lines[1].text == "diff --git a/x b/x")
    }

    @Test func contextLineWhoseContentStartsWithAtMarkers() throws {
        let body = """
        @@ -1,2 +1,2 @@
         @@ still context
        -old
        +new
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.lines[0].kind == .context)
        #expect(hunk.lines[0].text == "@@ still context")
        #expect(hunk.lines.count == 3)
    }

    // MARK: - CRLF is content, not a separator

    @Test func trailingCarriageReturnIsPreservedAsLineContent() throws {
        // Git separates patch lines with LF; CR is file content (verified against
        // real `git diff` bytes: 0d before 0a on CRLF sides, absent after LF conversion).
        let body = "@@ -1,2 +1,2 @@\n line one\r\n-line two\r\n+line TWO\r\n"

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.lines.count == 3)
        #expect(hunk.lines[0].text == "line one\r")
        #expect(hunk.lines[1].text == "line two\r")
        #expect(hunk.lines[2].text == "line TWO\r")
    }

    @Test func crlfToLfOnlyChangeKeepsCarriageReturnVisibleOnDeletionSide() throws {
        let body = "@@ -1,1 +1,1 @@\n-line one\r\n+line one\n"

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.lines[0].text == "line one\r")
        #expect(hunk.lines[1].text == "line one")
        #expect(hunk.lines[0].segments == [
            PatchLineSegment(text: "line one", isHighlighted: false),
            PatchLineSegment(text: "\r", isHighlighted: true),
        ])
        #expect(hunk.lines[1].segments == [
            PatchLineSegment(text: "line one", isHighlighted: false),
        ])
    }

    // MARK: - Errors

    @Test func lyingHeaderCountThrows() {
        let body = """
        @@ -1,5 +1,5 @@
         only
        -two
        +TWO
        """

        #expect(throws: HunkParserError.self) {
            try HunkParser.parse(body)
        }

        do {
            _ = try HunkParser.parse(body)
            Issue.record("Expected lineCountMismatch")
        } catch let error as HunkParserError {
            guard case let .lineCountMismatch(header, expectedOld, actualOld, expectedNew, actualNew) = error else {
                Issue.record("Wrong error case: \(error)")
                return
            }
            #expect(header == "@@ -1,5 +1,5 @@")
            #expect(expectedOld == 5)
            #expect(actualOld == 2)
            #expect(expectedNew == 5)
            #expect(actualNew == 2)
            #expect(error.errorDescription != nil)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func bodyThatDoesNotStartWithHunkHeaderThrowsInvalidHeader() {
        let body = """
        diff --git a/x b/x
        @@ -1,1 +1,1 @@
        -a
        +b
        """

        do {
            _ = try HunkParser.parse(body)
            Issue.record("Expected invalidHeader")
        } catch let error as HunkParserError {
            guard case let .invalidHeader(line) = error else {
                Issue.record("Wrong error case: \(error)")
                return
            }
            #expect(line == "diff --git a/x b/x")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func garbageLineInMiddleOfHunkThrowsUnexpectedLine() {
        let body = """
        @@ -1,2 +1,2 @@
         keep
        garbage
        +new
        """

        do {
            _ = try HunkParser.parse(body)
            Issue.record("Expected unexpectedLine")
        } catch let error as HunkParserError {
            guard case let .unexpectedLine(line) = error else {
                Issue.record("Wrong error case: \(error)")
                return
            }
            #expect(line == "garbage")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Intraline highlighting via parser

    @Test func pairsEqualDeletionAndAdditionBlocksForHighlight() throws {
        let body = """
        @@ -1,3 +1,3 @@
         keep
        -hello world
        +hello there
         end
        """

        let hunks = try HunkParser.parse(body)
        let hunk = try #require(hunks.first)
        let deletion = hunk.lines[1]
        let addition = hunk.lines[2]

        #expect(deletion.segments == [
            PatchLineSegment(text: "hello ", isHighlighted: false),
            PatchLineSegment(text: "world", isHighlighted: true),
        ])
        #expect(addition.segments == [
            PatchLineSegment(text: "hello ", isHighlighted: false),
            PatchLineSegment(text: "there", isHighlighted: true),
        ])
    }

    @Test func unequalDeletionAndAdditionBlocksGetNoHighlight() throws {
        let body = """
        @@ -1,4 +1,3 @@
         keep
        -one
        -two
        +only
         end
        """

        let hunks = try HunkParser.parse(body)
        let hunk = try #require(hunks.first)
        let changed = hunk.lines.filter { $0.kind != .context }
        #expect(changed.count == 3)
        #expect(changed.allSatisfy { line in
            line.segments.count == 1 && line.segments[0].isHighlighted == false
        })
    }

    @Test func interleavedChangeBlocksPairHighlightIndependently() throws {
        let body = """
        @@ -1,4 +1,4 @@
        -first old
        +first new
         middle
        -second left
        -second right
        +second LEFT
        +second RIGHT
        """

        let hunk = try #require(try HunkParser.parse(body).first)
        #expect(hunk.lines.map(\.kind) == [
            .deletion, .addition, .context, .deletion, .deletion, .addition, .addition,
        ])

        #expect(hunk.lines[0].segments == [
            PatchLineSegment(text: "first ", isHighlighted: false),
            PatchLineSegment(text: "old", isHighlighted: true),
        ])
        #expect(hunk.lines[1].segments == [
            PatchLineSegment(text: "first ", isHighlighted: false),
            PatchLineSegment(text: "new", isHighlighted: true),
        ])
        #expect(hunk.lines[2].segments == [
            PatchLineSegment(text: "middle", isHighlighted: false),
        ])
        #expect(hunk.lines[3].segments == [
            PatchLineSegment(text: "second ", isHighlighted: false),
            PatchLineSegment(text: "left", isHighlighted: true),
        ])
        #expect(hunk.lines[4].segments == [
            PatchLineSegment(text: "second ", isHighlighted: false),
            PatchLineSegment(text: "right", isHighlighted: true),
        ])
        #expect(hunk.lines[5].segments == [
            PatchLineSegment(text: "second ", isHighlighted: false),
            PatchLineSegment(text: "LEFT", isHighlighted: true),
        ])
        #expect(hunk.lines[6].segments == [
            PatchLineSegment(text: "second ", isHighlighted: false),
            PatchLineSegment(text: "RIGHT", isHighlighted: true),
        ])
    }
}
