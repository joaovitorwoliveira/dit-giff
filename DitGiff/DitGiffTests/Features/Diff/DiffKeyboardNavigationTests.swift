import Testing

@testable import DitGiff

@MainActor
struct DiffKeyboardNavigationTests {
    private let paths = ["a.swift", "b.swift", "c.swift", "d.bin"]

    // MARK: - Visible tree lines

    @Test func visibleLinesInterleaveDirectoriesAndFilesInTreeOrder() {
        let files = [
            sampleFile(path: "z-root.swift"),
            sampleFile(path: "a/nested/deep.swift"),
            sampleFile(path: "a/sibling.swift"),
            sampleFile(path: "b/other.swift"),
        ]
        let lines = DiffTreeVisibleLines.lines(
            from: DiffTree.build(files: files),
            isDirectoryOpen: { _ in true }
        )
        #expect(lines.map(\.path) == [
            "a/",
            "a/nested/",
            "a/nested/deep.swift",
            "a/sibling.swift",
            "b/",
            "b/other.swift",
            "z-root.swift",
        ])
        #expect(lines.filter(\.isDirectory).count == 3)
        #expect(lines.filter { !$0.isDirectory }.count == 4)
    }

    @Test func collapsedFolderDropsDescendantsFromVisibleLines() {
        let files = [
            sampleFile(path: "a/nested/deep.swift"),
            sampleFile(path: "a/sibling.swift"),
            sampleFile(path: "b/other.swift"),
        ]
        let closed: Set<String> = ["a/"]
        let lines = DiffTreeVisibleLines.lines(
            from: DiffTree.build(files: files),
            isDirectoryOpen: { !closed.contains($0) }
        )
        #expect(lines.map(\.path) == ["a/", "b/", "b/other.swift"])
    }

    @Test func reopeningFolderRestoresDescendantsInPlace() {
        let files = [
            sampleFile(path: "a/nested/deep.swift"),
            sampleFile(path: "a/sibling.swift"),
            sampleFile(path: "b/other.swift"),
        ]
        let tree = DiffTree.build(files: files)
        var closed: Set<String> = ["a/"]
        let collapsed = DiffTreeVisibleLines.lines(
            from: tree,
            isDirectoryOpen: { !closed.contains($0) }
        )
        #expect(collapsed.map(\.path) == ["a/", "b/", "b/other.swift"])

        closed.remove("a/")
        let reopened = DiffTreeVisibleLines.lines(
            from: tree,
            isDirectoryOpen: { !closed.contains($0) }
        )
        #expect(reopened.map(\.path) == [
            "a/",
            "a/nested/",
            "a/nested/deep.swift",
            "a/sibling.swift",
            "b/",
            "b/other.swift",
        ])
    }

    @Test func nextLineSkipsDescendantsOfCollapsedFolder() {
        let lines: [DiffTreeLine] = [
            .directory(path: "a/"),
            .directory(path: "b/"),
            .file(path: "b/other.swift"),
        ]
        #expect(
            DiffKeyboardNavigationResolver.nextLine(
                visibleLines: lines,
                focusedPath: "a/"
            ) == .moveTo(path: "b/")
        )
        #expect(
            DiffKeyboardNavigationResolver.previousLine(
                visibleLines: lines,
                focusedPath: "b/"
            ) == .moveTo(path: "a/")
        )
    }

    @Test func nextAndPreviousLineAreAntiInverse() {
        let lines: [DiffTreeLine] = [
            .directory(path: "a/"),
            .file(path: "a/one.swift"),
            .directory(path: "b/"),
            .file(path: "b/two.swift"),
        ]
        let forward = DiffKeyboardNavigationResolver.nextLine(
            visibleLines: lines,
            focusedPath: "a/one.swift"
        )
        #expect(forward == .moveTo(path: "b/"))
        #expect(forward != .moveTo(path: "a/"))
        guard case .moveTo(let landed) = forward else { return }
        let backward = DiffKeyboardNavigationResolver.previousLine(
            visibleLines: lines,
            focusedPath: landed
        )
        #expect(backward == .moveTo(path: "a/one.swift"))
        #expect(backward != forward)
    }

    // MARK: - next / previous line (path-array convenience)

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

    // MARK: - Reader key intent (the decision DiffViewer dispatches)

    @Test func rightArrowIntentIsNextFileNotPreviousOrScroll() {
        let intent = DiffReaderKeyIntentMapping.intent(
            for: DiffReaderKeyEvent(key: .rightArrow, modifiers: .init())
        )
        #expect(intent == .nextFile)
        #expect(intent != .previousFile)
        if case .scroll = intent {
            Issue.record("right arrow must not scroll")
        }
    }

    @Test func leftArrowIntentIsPreviousFileNotNextOrScroll() {
        let intent = DiffReaderKeyIntentMapping.intent(
            for: DiffReaderKeyEvent(key: .leftArrow, modifiers: .init())
        )
        #expect(intent == .previousFile)
        #expect(intent != .nextFile)
        if case .scroll = intent {
            Issue.record("left arrow must not scroll")
        }
    }

    @Test func leftRightArrowsDoNotProduceScrollIntent() {
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .leftArrow, modifiers: .init())
            ) != .scroll(.lineUp)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .leftArrow, modifiers: .init())
            ) != .scroll(.lineDown)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .rightArrow, modifiers: .init())
            ) != .scroll(.lineUp)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .rightArrow, modifiers: .init())
            ) != .scroll(.lineDown)
        )
    }

    @Test func verticalArrowsProduceLineScrollIntents() {
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .downArrow, modifiers: .init())
            ) == .scroll(.lineDown)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .upArrow, modifiers: .init())
            ) == .scroll(.lineUp)
        )
    }

    @Test func spaceAndPageKeysProducePaginationIntents() {
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .space, modifiers: .init())
            ) == .scroll(.pageDown)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .space, modifiers: .init(shift: true))
            ) == .scroll(.pageUp)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .pageDown, modifiers: .init())
            ) == .scroll(.pageDown)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .pageUp, modifiers: .init())
            ) == .scroll(.pageUp)
        )
    }

    @Test func nAndVProduceLetterIntents() {
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(
                    key: .character(DiffReaderLetterKey.nextUnreadFile),
                    modifiers: .init()
                )
            ) == .nextUnreadFile
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(
                    key: .character(DiffReaderLetterKey.toggleViewed),
                    modifiers: .init()
                )
            ) == .toggleViewed
        )
    }

    @Test func jkProduceNoReaderIntent() {
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .character("j"), modifiers: .init())
            ) == nil
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .character("k"), modifiers: .init())
            ) == nil
        )
    }

    @Test func commandOptionOrControlProducesNoIntent() {
        let keys: [DiffReaderKeyEvent.Key] = [
            .leftArrow, .rightArrow, .upArrow, .downArrow,
            .space, .pageUp, .pageDown,
            .character("n"), .character("v"),
        ]
        for key in keys {
            #expect(
                DiffReaderKeyIntentMapping.intent(
                    for: DiffReaderKeyEvent(key: key, modifiers: .init(command: true))
                ) == nil
            )
            #expect(
                DiffReaderKeyIntentMapping.intent(
                    for: DiffReaderKeyEvent(key: key, modifiers: .init(option: true))
                ) == nil
            )
            #expect(
                DiffReaderKeyIntentMapping.intent(
                    for: DiffReaderKeyEvent(key: key, modifiers: .init(control: true))
                ) == nil
            )
        }
    }

    @Test func rightArrowIntentAdvancesToNextVisibleTreeLineThroughModel() throws {
        let model = makeModel()
        let billingConfig = try #require(
            model.file(atPath: "Sources/Billing/BillingConfig.swift")
        )
        model.revealFileInReader(billingConfig)
        model.clearReaderScrollRequest()

        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .rightArrow, modifiers: .init()),
            isRepeat: false
        )
        #expect(intent == .nextFile)
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: modelDispatchActions(model)
        )

        // Next painted row under Billing/ is the next file, not a distant section neighbor.
        #expect(model.focusedFilePath == "Sources/Billing/BillingGuard.swift")
        #expect(model.readerScrollRequest?.path == "Sources/Billing/BillingGuard.swift")
    }

    @Test func leftArrowIntentRetreatsFocusedFileThroughModel() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)
        model.clearReaderScrollRequest()

        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .leftArrow, modifiers: .init()),
            isRepeat: false
        )
        #expect(intent == .previousFile)
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: modelDispatchActions(model)
        )

        #expect(model.focusedFilePath == "Sources/Billing/BillingConfig.swift")
        #expect(model.readerScrollRequest?.path == "Sources/Billing/BillingConfig.swift")
    }

    @Test func rightArrowOntoFolderDoesNotScrollReader() throws {
        let model = makeModel()
        let apiFile = try #require(
            model.file(atPath: "Sources/API/SubscriptionHandler.swift")
        )
        model.revealFileInReader(apiFile)
        model.clearReaderScrollRequest()

        model.goToNextFile()

        #expect(model.focusedFilePath == "Sources/Billing/")
        #expect(model.readerScrollRequest == nil)
    }

    /// Fails if `.nextFile` / `.previousFile` switch arms are swapped in the dispatch.
    @Test func dispatchNextFileDoesNotCallPreviousFile() {
        var called: [String] = []
        DiffReaderKeyIntentDispatch.perform(
            .nextFile,
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["nextFile"])
    }

    @Test func dispatchPreviousFileDoesNotCallNextFile() {
        var called: [String] = []
        DiffReaderKeyIntentDispatch.perform(
            .previousFile,
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["previousFile"])
    }

    @Test func dispatchNextFolderDoesNotCallPreviousFolder() {
        var called: [String] = []
        DiffReaderKeyIntentDispatch.perform(
            .nextFolder,
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["nextFolder"])
        #expect(!called.contains("previousFolder"))
    }

    @Test func dispatchPreviousFolderDoesNotCallNextFolder() {
        var called: [String] = []
        DiffReaderKeyIntentDispatch.perform(
            .previousFolder,
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["previousFolder"])
        #expect(!called.contains("nextFolder"))
    }

    @Test func dispatchOpenFocusedFolderDoesNotCallClose() {
        var called: [String] = []
        DiffReaderKeyIntentDispatch.perform(
            .openFocusedFolder,
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["openFocusedFolder"])
        #expect(!called.contains("closeFocusedFolder"))
    }

    @Test func dispatchCloseFocusedFolderDoesNotCallOpen() {
        var called: [String] = []
        DiffReaderKeyIntentDispatch.perform(
            .closeFocusedFolder,
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["closeFocusedFolder"])
        #expect(!called.contains("openFocusedFolder"))
    }

    @Test func dispatchNextUnreadAndToggleViewedAreDistinct() {
        var called: [String] = []
        DiffReaderKeyIntentDispatch.perform(
            .nextUnreadFile,
            actions: recordingDispatchActions { called.append($0) }
        )
        DiffReaderKeyIntentDispatch.perform(
            .toggleViewed,
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["nextUnreadFile", "toggleViewed"])
    }

    @Test func dispatchScrollDoesNotTouchFileActions() {
        var called: [String] = []
        var scrolled: DiffReaderScrollIntent?
        DiffReaderKeyIntentDispatch.perform(
            .scroll(.lineDown),
            actions: DiffReaderKeyIntentDispatch.Actions(
                goToNextFile: { called.append("nextFile") },
                goToPreviousFile: { called.append("previousFile") },
                goToNextFolder: { called.append("nextFolder") },
                goToPreviousFolder: { called.append("previousFolder") },
                openFocusedFolder: { called.append("openFocusedFolder") },
                closeFocusedFolder: { called.append("closeFocusedFolder") },
                goToNextUnreadFile: { called.append("nextUnreadFile") },
                toggleViewed: { called.append("toggleViewed") },
                scroll: { scrolled = $0 }
            )
        )
        #expect(called.isEmpty)
        #expect(scrolled == .lineDown)
    }

    @Test func fileAndScrollIntentsAllowKeyRepeatButFolderAndLetterDoNot() {
        #expect(DiffReaderKeyIntent.nextFile.allowsKeyRepeat)
        #expect(DiffReaderKeyIntent.previousFile.allowsKeyRepeat)
        #expect(DiffReaderKeyIntent.scroll(.lineDown).allowsKeyRepeat)
        #expect(DiffReaderKeyIntent.scroll(.pageUp).allowsKeyRepeat)
        #expect(DiffReaderKeyIntent.nextFolder.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.previousFolder.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.openFocusedFolder.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.closeFocusedFolder.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.nextUnreadFile.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.toggleViewed.allowsKeyRepeat == false)
    }

    // MARK: - Shift + arrows (folder intents)

    @Test func shiftDownIntentIsNextFolderNotPreviousOrScrollOrFile() {
        let intent = DiffReaderKeyIntentMapping.intent(
            for: DiffReaderKeyEvent(key: .downArrow, modifiers: .init(shift: true))
        )
        #expect(intent == .nextFolder)
        #expect(intent != .previousFolder)
        #expect(intent != .nextFile)
        #expect(intent != .previousFile)
        if case .scroll = intent {
            Issue.record("Shift+↓ must not scroll")
        }
    }

    @Test func shiftUpIntentIsPreviousFolderNotNextOrScrollOrFile() {
        let intent = DiffReaderKeyIntentMapping.intent(
            for: DiffReaderKeyEvent(key: .upArrow, modifiers: .init(shift: true))
        )
        #expect(intent == .previousFolder)
        #expect(intent != .nextFolder)
        #expect(intent != .nextFile)
        #expect(intent != .previousFile)
        if case .scroll = intent {
            Issue.record("Shift+↑ must not scroll")
        }
    }

    @Test func shiftRightIntentIsOpenFolderNotCloseOrFileOrScroll() {
        let intent = DiffReaderKeyIntentMapping.intent(
            for: DiffReaderKeyEvent(key: .rightArrow, modifiers: .init(shift: true))
        )
        #expect(intent == .openFocusedFolder)
        #expect(intent != .closeFocusedFolder)
        #expect(intent != .nextFile)
        #expect(intent != .previousFile)
        if case .scroll = intent {
            Issue.record("Shift+→ must not scroll")
        }
    }

    @Test func shiftLeftIntentIsCloseFolderNotOpenOrFileOrScroll() {
        let intent = DiffReaderKeyIntentMapping.intent(
            for: DiffReaderKeyEvent(key: .leftArrow, modifiers: .init(shift: true))
        )
        #expect(intent == .closeFocusedFolder)
        #expect(intent != .openFocusedFolder)
        #expect(intent != .nextFile)
        #expect(intent != .previousFile)
        if case .scroll = intent {
            Issue.record("Shift+← must not scroll")
        }
    }

    @Test func bareArrowsStillProduceFileAndScrollIntents() {
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .rightArrow, modifiers: .init())
            ) == .nextFile
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .leftArrow, modifiers: .init())
            ) == .previousFile
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .downArrow, modifiers: .init())
            ) == .scroll(.lineDown)
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .upArrow, modifiers: .init())
            ) == .scroll(.lineUp)
        )
    }

    @Test func shiftVerticalFolderIntentsRefuseKeyRepeat() {
        #expect(DiffReaderKeyIntent.nextFolder.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.previousFolder.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.openFocusedFolder.allowsKeyRepeat == false)
        #expect(DiffReaderKeyIntent.closeFocusedFolder.allowsKeyRepeat == false)
    }

    @Test func goToNextFolderLandsOnFolderLineNotFirstFile() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)
        model.clearReaderScrollRequest()

        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .downArrow, modifiers: .init(shift: true)),
            isRepeat: false
        )
        #expect(intent == .nextFolder)
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: modelDispatchActions(model)
        )

        // Tree: API → Billing → HTTP. From inside Billing, next folder line is HTTP/.
        #expect(model.focusedFilePath == "Sources/HTTP/")
        #expect(model.readerScrollRequest == nil)
    }

    @Test func goToPreviousFolderLandsOnFolderLineNotFirstFile() throws {
        let model = makeModel()
        let httpFile = try #require(model.file(atPath: "Sources/HTTP/APIClient.swift"))
        model.revealFileInReader(httpFile)
        model.clearReaderScrollRequest()

        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .upArrow, modifiers: .init(shift: true)),
            isRepeat: false
        )
        #expect(intent == .previousFolder)
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: modelDispatchActions(model)
        )

        #expect(model.focusedFilePath == "Sources/Billing/")
        #expect(model.readerScrollRequest == nil)
    }

    // MARK: - Viewer pipeline (guard + mapping + dispatch)

    @Test func viewerPipelineShiftDownDispatchesNextFolderNotScroll() throws {
        var called: [String] = []
        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .downArrow, modifiers: .init(shift: true)),
            isRepeat: false
        )
        #expect(intent == .nextFolder)
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["nextFolder"])
        #expect(!called.contains("scroll"))
    }

    @Test func viewerPipelineShiftUpDispatchesPreviousFolderNotScroll() throws {
        var called: [String] = []
        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .upArrow, modifiers: .init(shift: true)),
            isRepeat: false
        )
        #expect(intent == .previousFolder)
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: recordingDispatchActions { called.append($0) }
        )
        #expect(called == ["previousFolder"])
        #expect(!called.contains("scroll"))
    }

    @Test func viewerPipelineShiftAloneIsAllowedUnlikeHistoricalEmptyModifiersGuard() {
        let shiftDown = DiffReaderKeyEvent(key: .downArrow, modifiers: .init(shift: true))
        let shiftUp = DiffReaderKeyEvent(key: .upArrow, modifiers: .init(shift: true))
        #expect(shiftDown.modifiers.allowsReaderShortcut)
        #expect(shiftUp.modifiers.allowsReaderShortcut)
        #expect(shiftDown.modifiers.blocksReaderShortcut == false)
        #expect(
            DiffReaderKeyPressPipeline.intent(for: shiftDown, isRepeat: false) == .nextFolder
        )
        #expect(
            DiffReaderKeyPressPipeline.intent(for: shiftUp, isRepeat: false) == .previousFolder
        )
    }

    @Test func viewerPipelineShiftFolderIntentsIgnoreKeyRepeat() {
        let event = DiffReaderKeyEvent(key: .downArrow, modifiers: .init(shift: true))
        #expect(DiffReaderKeyPressPipeline.intent(for: event, isRepeat: false) == .nextFolder)
        #expect(DiffReaderKeyPressPipeline.intent(for: event, isRepeat: true) == nil)
    }

    @Test func viewerPipelineStillRejectsCommandOptionControl() {
        for modifiers in [
            DiffReaderKeyModifiers(shift: true, command: true),
            DiffReaderKeyModifiers(shift: true, option: true),
            DiffReaderKeyModifiers(shift: true, control: true),
        ] {
            #expect(modifiers.allowsReaderShortcut == false)
            #expect(
                DiffReaderKeyPressPipeline.intent(
                    for: DiffReaderKeyEvent(key: .downArrow, modifiers: modifiers),
                    isRepeat: false
                ) == nil
            )
        }
    }

    // MARK: - Reader display order matches tree

    @Test func readerDisplayOrderMatchesTreeDepthFirstWithDirectoriesBeforeFiles() {
        let files = [
            readerFile(path: "z-root.swift", hunkID: "z#0"),
            readerFile(path: "a/nested/deep.swift", hunkID: "a#0"),
            readerFile(path: "a/sibling.swift", hunkID: "a#1"),
            readerFile(path: "b/other.swift", hunkID: "b#0"),
        ]
        let tree = DiffTree.build(files: files)
        let treePaths = DiffReaderDisplayOrder.filesInTreeOrder(from: tree).map(\.path)
        let sectionPaths = DiffReaderDisplayOrder.sectionFiles(from: files).map(\.path)

        #expect(treePaths == [
            "a/nested/deep.swift",
            "a/sibling.swift",
            "b/other.swift",
            "z-root.swift",
        ])
        #expect(sectionPaths == treePaths)
    }

    @Test func sampleSectionFilesFollowTreeOrderNotPatchArrivalOrder() throws {
        let model = makeModel()
        // Literal expected order — do not recompute via DiffReaderDisplayOrder (tautology).
        #expect(model.sectionFiles.map(\.path) == [
            "Sources/API/SubscriptionHandler.swift",
            "Sources/Billing/BillingConfig.swift",
            "Sources/Billing/BillingGuard.swift",
            "Sources/Billing/InvoiceScheduler.swift",
            "Sources/Billing/PlanResolver.swift",
            "Sources/Billing/ProrationCalculator.swift",
            "Sources/HTTP/APIClient.swift",
            "Sources/Models/Subscription.swift",
            "Tests/BillingTests/AnnualBillingTests.swift",
            "Tests/__Snapshots__/InvoiceView@2x.png",
            "Tests/__Snapshots__/PlanPicker@2x.png",
        ])
        #expect(model.sectionFiles.map(\.path) == DiffSampleData.sectionPaths)
        #expect(model.sectionFiles.first?.path == "Sources/API/SubscriptionHandler.swift")
        let apiIndex = try #require(
            model.sectionFiles.map(\.path).firstIndex(of: "Sources/API/SubscriptionHandler.swift")
        )
        let billingIndex = try #require(
            model.sectionFiles.map(\.path).firstIndex(of: "Sources/Billing/BillingGuard.swift")
        )
        #expect(apiIndex < billingIndex)
    }

    /// The reported bug: closing a folder, navigating away, and returning must leave
    /// it closed. Arrow navigation must never call `ensureAncestorDirectoriesOpen`.
    @Test func arrowNavigationNeverReopensAClosedFolder() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)
        model.closeFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)
        #expect(model.focusedFilePath == "Sources/Billing/")

        model.goToNextFile()
        #expect(model.focusedFilePath == "Sources/HTTP/")
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)

        model.goToPreviousFile()
        #expect(model.focusedFilePath == "Sources/Billing/")
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)

        // Descendants stay out of the visible sequence while closed.
        let visible = model.visibleTreeLines.map(\.path)
        #expect(!visible.contains("Sources/Billing/BillingGuard.swift"))
        #expect(visible.contains("Sources/Billing/"))
    }

    @Test func collapsedFolderIsSkippedBySidewaysNavigation() throws {
        let model = makeModel()
        let api = try #require(model.file(atPath: "Sources/API/SubscriptionHandler.swift"))
        model.revealFileInReader(api)
        model.focusTreeLine("Sources/API/")
        model.closeFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/API/") == false)

        model.goToNextFile()
        // Next visible line after closed API/ is Billing/ — not a file inside API/.
        #expect(model.focusedFilePath == "Sources/Billing/")
        #expect(model.isDirectoryOpen("Sources/API/") == false)
    }

    // MARK: - Open / close under cursor

    @Test func openAndCloseFocusedFolderAreIdempotentNoOps() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)

        #expect(model.isDirectoryOpen("Sources/Billing/"))
        model.openFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/Billing/"))

        model.closeFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)
        #expect(model.focusedFilePath == "Sources/Billing/")
        model.closeFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)

        model.openFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/Billing/"))
    }

    @Test func shiftRightOpensFolderUnderCursorWhenCursorIsOnFolder() throws {
        let model = makeModel()
        model.focusTreeLine("Sources/Billing/")
        model.closeFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)

        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .rightArrow, modifiers: .init(shift: true)),
            isRepeat: false
        )
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: modelDispatchActions(model)
        )
        #expect(model.isDirectoryOpen("Sources/Billing/"))
        #expect(model.focusedFilePath == "Sources/Billing/")
    }

    @Test func shiftLeftOnFileClosesParentAndMovesCursorToFolder() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)

        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(key: .leftArrow, modifiers: .init(shift: true)),
            isRepeat: false
        )
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: modelDispatchActions(model)
        )
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)
        #expect(model.focusedFilePath == "Sources/Billing/")
    }

    @Test func openDoesNotCloseAndCloseDoesNotOpen() throws {
        let model = makeModel()
        model.focusTreeLine("Sources/HTTP/")
        #expect(model.isDirectoryOpen("Sources/HTTP/"))
        model.openFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/HTTP/"))

        model.closeFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/HTTP/") == false)
        model.openFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/HTTP/"))
        model.openFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/HTTP/"))
    }

    // MARK: - Folder line navigation (pure)

    private let multiFolderLines: [DiffTreeLine] = [
        .directory(path: "Features/"),
        .directory(path: "Features/Diff/"),
        .directory(path: "Features/Diff/Domain/"),
        .file(path: "Features/Diff/Domain/A.swift"),
        .file(path: "Features/Diff/Domain/B.swift"),
        .directory(path: "Features/Diff/Model/"),
        .file(path: "Features/Diff/Model/C.swift"),
        .file(path: "Features/Diff/Model/D.swift"),
        .directory(path: "Features/Diff/Views/"),
        .file(path: "Features/Diff/Views/E.swift"),
    ]

    @Test func nextFolderAdvancesToDirectoryLine() {
        let result = DiffKeyboardNavigationResolver.nextFolder(
            visibleLines: multiFolderLines,
            focusedPath: "Features/Diff/Domain/B.swift"
        )
        #expect(result == .moveTo(path: "Features/Diff/Model/"))
        #expect(result != .moveTo(path: "Features/Diff/Model/C.swift"))
    }

    @Test func previousFolderRetreatsToDirectoryLine() {
        let result = DiffKeyboardNavigationResolver.previousFolder(
            visibleLines: multiFolderLines,
            focusedPath: "Features/Diff/Model/C.swift"
        )
        #expect(result == .moveTo(path: "Features/Diff/Domain/"))
        #expect(result != .moveTo(path: "Features/Diff/Domain/A.swift"))
    }

    @Test func nextAndPreviousFolderAreAntiInverse() {
        let start = "Features/Diff/Domain/B.swift"
        let forward = DiffKeyboardNavigationResolver.nextFolder(
            visibleLines: multiFolderLines,
            focusedPath: start
        )
        guard case .moveTo(let landed) = forward else {
            Issue.record("expected forward folder navigation")
            return
        }
        #expect(landed == "Features/Diff/Model/")
        let backward = DiffKeyboardNavigationResolver.previousFolder(
            visibleLines: multiFolderLines,
            focusedPath: landed
        )
        #expect(backward == .moveTo(path: "Features/Diff/Domain/"))
        #expect(backward != forward)
    }

    @Test func nextFolderAtLastFolderStays() {
        let result = DiffKeyboardNavigationResolver.nextFolder(
            visibleLines: multiFolderLines,
            focusedPath: "Features/Diff/Views/E.swift"
        )
        #expect(result == .stay)
    }

    @Test func previousFolderAtFirstFolderStays() {
        let result = DiffKeyboardNavigationResolver.previousFolder(
            visibleLines: multiFolderLines,
            focusedPath: "Features/"
        )
        #expect(result == .stay)
    }

    @Test func folderNavigationStaysWhenVisibleLinesAreEmpty() {
        #expect(
            DiffKeyboardNavigationResolver.nextFolder(visibleLines: [], focusedPath: nil) == .stay
        )
        #expect(
            DiffKeyboardNavigationResolver.previousFolder(visibleLines: [], focusedPath: nil)
                == .stay
        )
    }

    @Test func folderNavigationWithNilCursorGoesToFirstOrLastDirectory() {
        #expect(
            DiffKeyboardNavigationResolver.nextFolder(
                visibleLines: multiFolderLines,
                focusedPath: nil
            ) == .moveTo(path: "Features/")
        )
        #expect(
            DiffKeyboardNavigationResolver.previousFolder(
                visibleLines: multiFolderLines,
                focusedPath: nil
            ) == .moveTo(path: "Features/Diff/Views/")
        )
    }

    @Test func folderPathForToggleUsesDirectoryUnderCursorOrParentOfFile() {
        #expect(
            DiffKeyboardNavigationResolver.folderPathForToggle(
                focusedPath: "Sources/Billing/",
                parentDirectoryOfFile: { _ in "" }
            ) == "Sources/Billing/"
        )
        #expect(
            DiffKeyboardNavigationResolver.folderPathForToggle(
                focusedPath: "Sources/Billing/Guard.swift",
                parentDirectoryOfFile: { _ in "Sources/Billing/" }
            ) == "Sources/Billing/"
        )
        #expect(
            DiffKeyboardNavigationResolver.folderPathForToggle(
                focusedPath: "README.md",
                parentDirectoryOfFile: { _ in "" }
            ) == nil
        )
    }

    // MARK: - v on folder

    @Test func toggleViewedOnFolderMarksDescendantsAndClosesFolder() throws {
        let model = makeModel()
        model.focusTreeLine("Sources/Billing/")
        let billing = try #require(
            DiffTreeLookup.directory(at: "Sources/Billing/", in: model.fileTree)
        )
        #expect(model.viewedState(for: billing) != .all)
        #expect(model.isDirectoryOpen("Sources/Billing/"))

        let intent = DiffReaderKeyPressPipeline.intent(
            for: DiffReaderKeyEvent(
                key: .character(DiffReaderLetterKey.toggleViewed),
                modifiers: .init()
            ),
            isRepeat: false
        )
        DiffReaderKeyIntentDispatch.perform(
            try #require(intent),
            actions: modelDispatchActions(model)
        )

        #expect(model.viewedState(for: billing) == .all)
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)
        for file in billing.descendantFiles {
            #expect(model.isViewed(file))
        }
    }

    @Test func toggleViewedOnFullyViewedFolderClearsMarksAndReopens() throws {
        let model = makeModel()
        model.focusTreeLine("Sources/Billing/")
        let billing = try #require(
            DiffTreeLookup.directory(at: "Sources/Billing/", in: model.fileTree)
        )
        model.toggleViewedOnFocusedFile()
        #expect(model.viewedState(for: billing) == .all)
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)

        model.toggleViewedOnFocusedFile()
        #expect(model.viewedState(for: billing) == .none)
        #expect(model.isDirectoryOpen("Sources/Billing/"))
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

    @Test func nextUnreadMayOpenCollapsedFolder() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        // Close Billing and park the cursor on the folder line.
        model.revealFileInReader(billingGuard)
        model.closeFocusedFolder()
        #expect(model.isDirectoryOpen("Sources/Billing/") == false)

        // Mark every section file read except BillingGuard.
        for file in model.sectionFiles where file.path != billingGuard.path {
            if file.hunks.isEmpty {
                model.setViewed(true, for: file)
            } else {
                for hunk in file.hunks where !model.isRead(hunk) {
                    model.toggleRead(hunk)
                }
            }
        }

        model.goToNextUnreadFile()

        #expect(model.focusedFilePath == billingGuard.path)
        #expect(model.isDirectoryOpen("Sources/Billing/"))
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

    private func sampleFile(path: String) -> DiffFile {
        DiffFile(
            path: path,
            status: .modified,
            additions: 1,
            deletions: 0,
            hunks: [],
            body: .noContent
        )
    }

    private func readerFile(path: String, hunkID: String) -> DiffFile {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return DiffFile(
            path: path,
            status: .added,
            additions: 1,
            deletions: 0,
            hunks: [
                DiffHunk(
                    id: hunkID,
                    filePath: path,
                    header: "@@ -1 +1 @@",
                    location: "\(name):1",
                    note: nil,
                    explanation: nil,
                    reply: nil,
                    lines: [
                        DiffLine(
                            oldNumber: nil,
                            newNumber: 1,
                            kind: .addition,
                            segments: [DiffLineSegment(text: "x")]
                        )
                    ]
                )
            ],
            body: .text
        )
    }

    /// Same action wiring `DiffViewer.handleKeyPress` uses for model-side intents.
    private func modelDispatchActions(_ model: DiffModel) -> DiffReaderKeyIntentDispatch.Actions {
        DiffReaderKeyIntentDispatch.Actions(
            goToNextFile: { model.goToNextFile() },
            goToPreviousFile: { model.goToPreviousFile() },
            goToNextFolder: { model.goToNextFolder() },
            goToPreviousFolder: { model.goToPreviousFolder() },
            openFocusedFolder: { model.openFocusedFolder() },
            closeFocusedFolder: { model.closeFocusedFolder() },
            goToNextUnreadFile: { model.goToNextUnreadFile() },
            toggleViewed: { model.toggleViewedOnFocusedFile() },
            scroll: { _ in Issue.record("scroll must not run in file-nav dispatch tests") }
        )
    }

    private func recordingDispatchActions(
        _ record: @escaping (String) -> Void
    ) -> DiffReaderKeyIntentDispatch.Actions {
        DiffReaderKeyIntentDispatch.Actions(
            goToNextFile: { record("nextFile") },
            goToPreviousFile: { record("previousFile") },
            goToNextFolder: { record("nextFolder") },
            goToPreviousFolder: { record("previousFolder") },
            openFocusedFolder: { record("openFocusedFolder") },
            closeFocusedFolder: { record("closeFocusedFolder") },
            goToNextUnreadFile: { record("nextUnreadFile") },
            toggleViewed: { record("toggleViewed") },
            scroll: { _ in record("scroll") }
        )
    }

    @Test func goToNextFileRevealsNeighborFileAndFocusesIt() throws {
        let model = makeModel()
        let config = try #require(model.file(atPath: "Sources/Billing/BillingConfig.swift"))
        let guardFile = try #require(model.file(atPath: "Sources/Billing/BillingGuard.swift"))
        model.revealFileInReader(config)
        model.clearReaderScrollRequest()

        model.goToNextFile()

        #expect(model.focusedFilePath == guardFile.path)
        #expect(model.readerScrollRequest?.path == guardFile.path)
    }

    @Test func goToNextFileOnKeyRepeatReplacesInFlightJumpWithNewNonce() throws {
        let model = makeModel()
        let first = try #require(model.file(atPath: "Sources/Billing/BillingConfig.swift"))
        let second = try #require(model.file(atPath: "Sources/Billing/BillingGuard.swift"))
        let third = try #require(model.file(atPath: "Sources/Billing/InvoiceScheduler.swift"))
        model.revealFileInReader(first)
        let firstNonce = try #require(model.readerScrollRequest?.nonce)

        model.goToNextFile(isKeyRepeat: true)
        let secondRequest = try #require(model.readerScrollRequest)
        #expect(model.focusedFilePath == second.path)
        #expect(secondRequest.path == second.path)
        #expect(secondRequest.nonce != firstNonce)
        #expect(secondRequest.scrollStyle == .rapid)

        model.goToNextFile(isKeyRepeat: true)
        let thirdRequest = try #require(model.readerScrollRequest)
        #expect(model.focusedFilePath == third.path)
        #expect(thirdRequest.path == third.path)
        #expect(thirdRequest.nonce != secondRequest.nonce)
        #expect(thirdRequest.scrollStyle == .rapid)
    }

    @Test func goToNextFileWithoutKeyRepeatUsesSettledScrollStyle() throws {
        let model = makeModel()
        let config = try #require(model.file(atPath: "Sources/Billing/BillingConfig.swift"))
        model.revealFileInReader(config)
        model.clearReaderScrollRequest()

        model.goToNextFile(isKeyRepeat: false)

        #expect(model.readerScrollRequest?.scrollStyle == .settled)
    }

    // MARK: - Rapid repeat burst release (viewer policy wiring)

    @Test func repeatBurstReleasePolicyMatchesViewerWiring() throws {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        let model = makeModel()
        let first = try #require(model.file(atPath: "Sources/Billing/BillingConfig.swift"))
        let second = try #require(model.file(atPath: "Sources/Billing/BillingGuard.swift"))
        model.revealFileInReader(first)
        model.clearReaderScrollRequest()

        let nonceBefore = model.readerScrollRequest?.nonce
        model.goToNextFile(isKeyRepeat: true)
        let rapid = try #require(model.readerScrollRequest)
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: rapid.scrollStyle == .rapid && rapid.nonce != nonceBefore,
            filePath: rapid.path
        )
        #expect(model.focusedFilePath == second.path)

        let release = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .rightArrow, modifiers: .init())
        )
        #expect(release == .settled(path: second.path))
    }

    @Test func bareKeyUpWithoutRepeatBurstIsIgnoredByPolicy() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .rightArrow, modifiers: .init())
        )
        #expect(outcome == .ignored)
    }

    @Test func oppositeArrowKeyUpClearsBurstWithoutSettlement() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: "a.swift"
        )
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .leftArrow, modifiers: .init())
        )
        #expect(outcome == .ignored)
        #expect(policy.burst == nil)
    }

    @Test func modifiedArrowKeyUpClearsBurstWithoutSettlement() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .previous,
            producedNewRapidRequest: true,
            filePath: "b.swift"
        )
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .leftArrow, modifiers: .init(shift: true))
        )
        #expect(outcome == .ignored)
        #expect(policy.burst == nil)
    }

    @Test func goToNextUnreadSkipsReadFilesIncludingViewedZeroHunk() throws {
        let model = makeModel()
        let section = model.sectionFiles
        let first = try #require(section.first)
        model.revealFileInReader(first)

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
