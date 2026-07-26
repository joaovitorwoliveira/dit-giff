import Testing

@testable import DitGiff

@MainActor
struct DiffKeyboardNavigationTests {
    private let paths = ["a.swift", "b.swift", "c.swift", "d.bin"]

    // MARK: - j / k order

    @Test func nextFileAdvancesInOrder() {
        let result = DiffKeyboardNavigationResolver.nextFile(
            orderedPaths: paths,
            focusedPath: "b.swift"
        )
        #expect(result == .moveTo(path: "c.swift"))
    }

    @Test func previousFileRetreatsInOrder() {
        let result = DiffKeyboardNavigationResolver.previousFile(
            orderedPaths: paths,
            focusedPath: "c.swift"
        )
        #expect(result == .moveTo(path: "b.swift"))
    }

    @Test func nextFileWithNilCursorGoesToFirst() {
        let result = DiffKeyboardNavigationResolver.nextFile(
            orderedPaths: paths,
            focusedPath: nil
        )
        #expect(result == .moveTo(path: "a.swift"))
    }

    @Test func previousFileWithNilCursorGoesToLast() {
        let result = DiffKeyboardNavigationResolver.previousFile(
            orderedPaths: paths,
            focusedPath: nil
        )
        #expect(result == .moveTo(path: "d.bin"))
    }

    @Test func nextFileAtEndDoesNotWrap() {
        let result = DiffKeyboardNavigationResolver.nextFile(
            orderedPaths: paths,
            focusedPath: "d.bin"
        )
        #expect(result == .stay)
    }

    @Test func previousFileAtStartDoesNotWrap() {
        let result = DiffKeyboardNavigationResolver.previousFile(
            orderedPaths: paths,
            focusedPath: "a.swift"
        )
        #expect(result == .stay)
    }

    @Test func nextAndPreviousStayWhenThereAreNoFiles() {
        #expect(
            DiffKeyboardNavigationResolver.nextFile(orderedPaths: [], focusedPath: nil) == .stay
        )
        #expect(
            DiffKeyboardNavigationResolver.previousFile(orderedPaths: [], focusedPath: nil) == .stay
        )
    }

    // MARK: - n next unread

    @Test func nextUnreadFindsForward() {
        let read: Set<String> = ["a.swift", "b.swift"]
        let result = DiffKeyboardNavigationResolver.nextUnreadFile(
            orderedPaths: paths,
            focusedPath: "a.swift",
            isRead: { read.contains($0) }
        )
        #expect(result == .moveTo(path: "c.swift"))
    }

    @Test func nextUnreadWrapsFromTheTop() {
        let read: Set<String> = ["b.swift", "c.swift", "d.bin"]
        let result = DiffKeyboardNavigationResolver.nextUnreadFile(
            orderedPaths: paths,
            focusedPath: "c.swift",
            isRead: { read.contains($0) }
        )
        #expect(result == .moveTo(path: "a.swift"))
    }

    @Test func nextUnreadStaysWhenEverythingIsRead() {
        let result = DiffKeyboardNavigationResolver.nextUnreadFile(
            orderedPaths: paths,
            focusedPath: "a.swift",
            isRead: { _ in true }
        )
        #expect(result == .stay)
    }

    @Test func nextUnreadWithNilCursorStartsFromTheTop() {
        let read: Set<String> = ["a.swift"]
        let result = DiffKeyboardNavigationResolver.nextUnreadFile(
            orderedPaths: paths,
            focusedPath: nil,
            isRead: { read.contains($0) }
        )
        #expect(result == .moveTo(path: "b.swift"))
    }

    // MARK: - Read decision (zero-hunk and text)

    @Test func zeroHunkFileIsUnreadUntilViewed() {
        #expect(
            DiffFileReadDecision.isRead(
                path: "icon.png",
                hunkIDs: [],
                viewedPaths: [],
                readHunkIDs: []
            ) == false
        )
    }

    @Test func zeroHunkFileIsReadAfterViewed() {
        #expect(
            DiffFileReadDecision.isRead(
                path: "icon.png",
                hunkIDs: [],
                viewedPaths: ["icon.png"],
                readHunkIDs: []
            )
        )
    }

    @Test func textFileIsReadOnlyWhenEveryHunkIsRead() {
        let hunks = ["a.swift#0", "a.swift#1"]
        #expect(
            DiffFileReadDecision.isRead(
                path: "a.swift",
                hunkIDs: hunks,
                viewedPaths: [],
                readHunkIDs: ["a.swift#0"]
            ) == false
        )
        #expect(
            DiffFileReadDecision.isRead(
                path: "a.swift",
                hunkIDs: hunks,
                viewedPaths: [],
                readHunkIDs: Set(hunks)
            )
        )
    }

    @Test func viewedTextFileCountsAsReadEvenWithoutHunkTicks() {
        #expect(
            DiffFileReadDecision.isRead(
                path: "a.swift",
                hunkIDs: ["a.swift#0"],
                viewedPaths: ["a.swift"],
                readHunkIDs: []
            )
        )
    }

    // MARK: - Model wiring

    private func makeModel() -> DiffModel {
        DiffModel(replyDelay: ImmediateReplyDelay(), readHunkBaseline: DiffSampleData.readHunkBaseline)
    }

    @Test func goToNextFileRevealsTheNeighborAndFocusesIt() throws {
        let model = makeModel()
        let first = try #require(model.sectionFiles.first)
        let second = try #require(model.sectionFiles.dropFirst().first)
        model.revealFileInReader(first)
        model.clearReaderScrollRequest()

        model.goToNextFile()

        #expect(model.focusedFilePath == second.path)
        #expect(model.readerScrollRequest?.path == second.path)
    }

    @Test func goToNextUnreadSkipsReadFilesIncludingViewedZeroHunk() throws {
        let model = makeModel()
        let section = model.sectionFiles
        let first = try #require(section.first)
        model.revealFileInReader(first)

        // Mark every section file read except the last, including zero-hunk via viewed.
        for file in section.dropLast() {
            if file.hunks.isEmpty {
                model.setViewed(true, for: file)
            } else {
                for hunk in file.hunks {
                    if !model.isRead(hunk) {
                        model.toggleRead(hunk)
                    }
                }
            }
        }
        let last = try #require(section.last)
        #expect(
            DiffFileReadDecision.isRead(
                path: last.path,
                hunkIDs: last.hunks.map(\.id),
                viewedPaths: model.viewedPaths,
                readHunkIDs: model.readHunkIDs
            ) == false
        )

        model.goToNextUnreadFile()

        #expect(model.focusedFilePath == last.path)
    }

    @Test func toggleViewedOnFocusedFileTogglesTheCursorFile() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)
        #expect(model.isViewed(billingGuard) == false)

        model.toggleViewedOnFocusedFile()

        #expect(model.isViewed(billingGuard))
    }
}

private struct ImmediateReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}
