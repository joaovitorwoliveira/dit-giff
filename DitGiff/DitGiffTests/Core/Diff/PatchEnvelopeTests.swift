import Foundation
import Testing

@testable import DitGiff

nonisolated struct PatchEnvelopeTests {

    // MARK: - Modified

    @Test func parsesModifiedTextFile() throws {
        let unified = """
        diff --git a/keep.txt b/keep.txt
        index d95f3ad..5ea2ed4 100644
        --- a/keep.txt
        +++ b/keep.txt
        @@ -1 +1 @@
        -content
        +changed
        """
        let raw = ":100644 100644 d95f3ad 5ea2ed4 M\0keep.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.path == "keep.txt")
        #expect(file.oldPath == nil)
        #expect(file.change == .modified)
        #expect(file.oldMode == "100644")
        #expect(file.newMode == "100644")
        #expect(file.body == .text("""
        @@ -1 +1 @@
        -content
        +changed
        """))
    }

    // MARK: - Added / deleted / empty

    @Test func parsesAddedAndDeletedFiles() throws {
        let unified = """
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        index 8616c68..0000000
        --- a/gone.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -to-delete
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..3e75765
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1 @@
        +hello
        """
        let raw =
            ":100644 000000 8616c68 0000000 D\0gone.txt\0"
            + ":000000 100644 0000000 3e75765 A\0new.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.count == 2)

        #expect(files[0].path == "gone.txt")
        #expect(files[0].change == .deleted)
        #expect(files[0].oldMode == "100644")
        #expect(files[0].newMode == nil)
        guard case let .text(deletedBody) = files[0].body else {
            Issue.record("expected text body for deleted file")
            return
        }
        #expect(deletedBody.hasPrefix("@@ -1 +0,0 @@"))

        #expect(files[1].path == "new.txt")
        #expect(files[1].change == .added)
        #expect(files[1].oldMode == nil)
        #expect(files[1].newMode == "100644")
        guard case let .text(addedBody) = files[1].body else {
            Issue.record("expected text body for added file")
            return
        }
        #expect(addedBody.contains("+hello"))
    }

    @Test func parsesNewEmptyFileAsNoContent() throws {
        let unified = """
        diff --git a/empty.txt b/empty.txt
        new file mode 100644
        index 0000000..e69de29
        """
        let raw = ":000000 100644 0000000 e69de29 A\0empty.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files == [
            PatchFileEnvelope(
                path: "empty.txt",
                oldPath: nil,
                change: .added,
                body: .noContent,
                oldMode: nil,
                newMode: "100644"
            ),
        ])
    }

    // MARK: - Rename / copy

    @Test func parsesRename() throws {
        let unified = """
        diff --git a/oldname.txt b/newname.txt
        similarity index 100%
        rename from oldname.txt
        rename to newname.txt
        """
        let raw = ":100644 100644 5a0ed06 5a0ed06 R100\0oldname.txt\0newname.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.path == "newname.txt")
        #expect(file.oldPath == "oldname.txt")
        #expect(file.change == .renamed(from: "oldname.txt"))
        #expect(file.body == .noContent)
    }

    @Test func parsesCopy() throws {
        let unified = """
        diff --git a/source.txt b/copy.txt
        similarity index 100%
        copy from source.txt
        copy to copy.txt
        """
        let raw = ":100644 100644 abc1234 abc1234 C100\0source.txt\0copy.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        let file = try #require(files.first)
        #expect(file.path == "copy.txt")
        #expect(file.oldPath == "source.txt")
        #expect(file.change == .copied(from: "source.txt"))
        #expect(file.body == .noContent)
    }

    // MARK: - Paths with spaces and accents

    @Test func parsesPathsWithSpacesAndAccents() throws {
        let unified = """
        diff --git a/arquivo café.txt b/arquivo café.txt
        new file mode 100644
        index 0000000..9fb2114
        --- /dev/null
        +++ b/arquivo café.txt
        @@ -0,0 +1 @@
        +café content
        diff --git a/path with space/nested.txt b/path with space/nested.txt
        new file mode 100644
        index 0000000..587be6b
        --- /dev/null
        +++ b/path with space/nested.txt
        @@ -0,0 +1 @@
        +x
        """
        let raw =
            ":000000 100644 0000000 9fb2114 A\0arquivo café.txt\0"
            + ":000000 100644 0000000 587be6b A\0path with space/nested.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.map(\.path) == ["arquivo café.txt", "path with space/nested.txt"])
        #expect(files[0].change == .added)
        #expect(files[1].change == .added)
        guard case let .text(accentBody) = files[0].body else {
            Issue.record("expected text body")
            return
        }
        #expect(accentBody.contains("+café content"))
    }

    // MARK: - Binary / submodule / mode-only

    @Test func parsesBinaryFile() throws {
        let unified = """
        diff --git a/binary.bin b/binary.bin
        new file mode 100644
        index 0000000..eaf36c1
        Binary files /dev/null and b/binary.bin differ
        """
        let raw = ":000000 100644 0000000 eaf36c1 A\0binary.bin\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.first?.body == .binary)
        #expect(files.first?.change == .added)
    }

    @Test func parsesSubmoduleByMode() throws {
        let unified = """
        diff --git a/vendor b/vendor
        new file mode 160000
        index 0000000..0be9ccb
        --- /dev/null
        +++ b/vendor
        @@ -0,0 +1 @@
        +Subproject commit 0be9ccb5546fbf43ba9b891197bd01a63eba9813
        """
        let raw = ":000000 160000 0000000 0be9ccb A\0vendor\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        let file = try #require(files.first)
        #expect(file.path == "vendor")
        #expect(file.change == .added)
        #expect(file.newMode == "160000")
        #expect(file.body == .submodule)
    }

    @Test func parsesModeOnlyChangeAsNoContent() throws {
        let unified = """
        diff --git a/mode.txt b/mode.txt
        old mode 100644
        new mode 100755
        """
        let raw = ":100644 100755 9ec8906 9ec8906 M\0mode.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files == [
            PatchFileEnvelope(
                path: "mode.txt",
                oldPath: nil,
                change: .modified,
                body: .noContent,
                oldMode: "100644",
                newMode: "100755"
            ),
        ])
    }

    // MARK: - Content that looks like a file header

    @Test func doesNotTreatContentLineAsNewFileHeader() throws {
        let unified = """
        diff --git a/f.txt b/f.txt
        index 31dcc35..4bc132f 100644
        --- a/f.txt
        +++ b/f.txt
        @@ -1 +1,3 @@
        -normal
        +line1
        +diff --git a/fake b/fake
        +line3
        """
        let raw = ":100644 100644 31dcc35 4bc132f M\0f.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.count == 1)
        guard case let .text(body) = files[0].body else {
            Issue.record("expected text body")
            return
        }
        #expect(body.contains("+diff --git a/fake b/fake"))
        #expect(body.hasPrefix("@@ -1 +1,3 @@"))
    }

    // MARK: - No newline at EOF / empty patch

    @Test func preservesNoNewlineMarkerInTextBody() throws {
        let unified = """
        diff --git a/nonewline.txt b/nonewline.txt
        index 2c9d574..13fa18b 100644
        --- a/nonewline.txt
        +++ b/nonewline.txt
        @@ -1 +1 @@
        -no-nl
        \\ No newline at end of file
        +no-nlX
        \\ No newline at end of file
        """
        let raw = ":100644 100644 2c9d574 13fa18b M\0nonewline.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        guard case let .text(body) = files[0].body else {
            Issue.record("expected text body")
            return
        }
        #expect(body.contains("\\ No newline at end of file"))
        #expect(body.contains("+no-nlX"))
    }

    @Test func emptyPatchYieldsEmptyList() throws {
        let files = try PatchEnvelope.parse(unifiedDiff: "", rawDiff: "")
        #expect(files.isEmpty)
    }

    @Test func crlfPatchLinesDoNotSwallowFollowingFileHeader() throws {
        // Real git embeds CR in the line body of CRLF files: "+CRLF\r\n".
        // Swift treats "\r\n" as one Character — splitting must still see U+000A.
        let unified =
            "diff --git a/crlf.txt b/crlf.txt\n"
            + "index aaa..bbb 100644\n"
            + "--- a/crlf.txt\n"
            + "+++ b/crlf.txt\n"
            + "@@ -1,2 +1,2 @@\n"
            + "-crlf\r\n"
            + "+CRLF\r\n"
            + " line2\r\n"
            + "diff --git a/delete.txt b/delete.txt\n"
            + "deleted file mode 100644\n"
            + "index ccc..0000000\n"
            + "--- a/delete.txt\n"
            + "+++ /dev/null\n"
            + "@@ -1 +0,0 @@\n"
            + "-delete-me\n"
        let raw =
            ":100644 100644 aaa bbb M\0crlf.txt\0"
            + ":100644 000000 ccc 0000000 D\0delete.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.map(\.path) == ["crlf.txt", "delete.txt"])
        #expect(files[0].change == .modified)
        #expect(files[1].change == .deleted)
        guard case let .text(crlfBody) = files[0].body else {
            Issue.record("crlf.txt should have a text body")
            return
        }
        #expect(crlfBody.hasPrefix("@@"))
        #expect(!crlfBody.contains("diff --git"))
        guard case let .text(deleteBody) = files[1].body else {
            Issue.record("delete.txt should have its own text body")
            return
        }
        #expect(deleteBody.contains("-delete-me"))
    }

    // MARK: - Path matching (not position)

    @Test func matchesByDestinationPathWhenOrdersDiverge() throws {
        // Unified order: zebra, alpha. Raw order: alpha, zebra.
        let unified = """
        diff --git a/zebra.txt b/zebra.txt
        index 111..222 100644
        --- a/zebra.txt
        +++ b/zebra.txt
        @@ -1 +1 @@
        -z-old
        +z-new
        diff --git a/alpha.txt b/alpha.txt
        index 333..444 100644
        --- a/alpha.txt
        +++ b/alpha.txt
        @@ -1 +1 @@
        -a-old
        +a-new
        """
        let raw =
            ":100644 100644 333 444 M\0alpha.txt\0"
            + ":100644 100644 111 222 M\0zebra.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.map(\.path) == ["alpha.txt", "zebra.txt"])

        guard case let .text(alphaBody) = files[0].body else {
            Issue.record("alpha should keep its own body")
            return
        }
        #expect(alphaBody.contains("+a-new"))
        #expect(!alphaBody.contains("z-"))

        guard case let .text(zebraBody) = files[1].body else {
            Issue.record("zebra should keep its own body")
            return
        }
        #expect(zebraBody.contains("+z-new"))
        #expect(!zebraBody.contains("a-"))
    }

    @Test func matchesRenameByDestinationPathAcrossReorderedLists() throws {
        let unified = """
        diff --git a/keep.txt b/keep.txt
        index aaa..bbb 100644
        --- a/keep.txt
        +++ b/keep.txt
        @@ -1 +1 @@
        -old
        +new
        diff --git a/from.txt b/to.txt
        similarity index 100%
        rename from from.txt
        rename to to.txt
        """
        // Raw lists the rename first — opposite of unified.
        let raw =
            ":100644 100644 ccc ccc R100\0from.txt\0to.txt\0"
            + ":100644 100644 aaa bbb M\0keep.txt\0"

        let files = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        #expect(files.map(\.path) == ["to.txt", "keep.txt"])
        #expect(files[0].change == .renamed(from: "from.txt"))
        #expect(files[0].body == .noContent)
        guard case let .text(keepBody) = files[1].body else {
            Issue.record("keep.txt should have text body")
            return
        }
        #expect(keepBody.contains("+new"))
    }

    // MARK: - Errors

    @Test func rejectsOrphanRawPath() {
        let unified = """
        diff --git a/a.txt b/a.txt
        index 111..222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -a
        +b
        """
        let raw =
            ":100644 100644 111 222 M\0a.txt\0"
            + ":100644 100644 333 444 M\0orphan.txt\0"

        #expect(throws: PatchEnvelopeError.unmatchedRawPath("orphan.txt")) {
            _ = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        }
    }

    @Test func rejectsOrphanPatchPath() {
        let unified = """
        diff --git a/a.txt b/a.txt
        index 111..222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -a
        +b
        diff --git a/ghost.txt b/ghost.txt
        index 333..444 100644
        --- a/ghost.txt
        +++ b/ghost.txt
        @@ -1 +1 @@
        -g
        +h
        """
        let raw = ":100644 100644 111 222 M\0a.txt\0"

        #expect(throws: PatchEnvelopeError.unmatchedPatchPath("ghost.txt")) {
            _ = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        }
    }

    @Test func rejectsPreambleBeforeFirstDiffGit() {
        let unified = """
        not a patch
        diff --git a/a.txt b/a.txt
        """
        let raw = ":100644 100644 aaa bbb M\0a.txt\0"

        #expect(throws: PatchEnvelopeError.unexpectedPatchPreamble("not a patch")) {
            _ = try PatchEnvelope.parse(unifiedDiff: unified, rawDiff: raw)
        }
    }

    @Test func rejectsMalformedRawEntry() {
        #expect {
            try PatchEnvelope.parseRaw("not-raw")
        } throws: { error in
            guard let error = error as? PatchEnvelopeError,
                  case .malformedRawEntry = error
            else {
                return false
            }
            return true
        }
    }
}
