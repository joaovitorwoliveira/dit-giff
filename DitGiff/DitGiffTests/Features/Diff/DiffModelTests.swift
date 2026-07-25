import Testing

@testable import DitGiff

/// The fake round trip with the waiting taken out, so the tests read the same flow the
/// screen does without spending a second on it.
private struct ImmediateReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}

private extension DiffTreeNode {
    var asDirectory: DiffTreeDirectory? {
        guard case let .directory(directory) = self else { return nil }
        return directory
    }

    var asFile: DiffFile? {
        guard case let .file(file, _) = self else { return nil }
        return file
    }
}

@MainActor
struct DiffModelTests {
    private func makeModel(readHunkBaseline: Int = DiffSampleData.readHunkBaseline) -> DiffModel {
        DiffModel(replyDelay: ImmediateReplyDelay(), readHunkBaseline: readHunkBaseline)
    }

    private func file(_ path: String, in model: DiffModel) throws -> DiffFile {
        try #require(model.file(atPath: path))
    }

    private func hunk(_ id: String, in model: DiffModel) throws -> DiffHunk {
        try #require(model.hunk(withID: id))
    }

    // MARK: - Viewed and collapsed

    @Test func opensWithThePrototypesViewedFilesCollapsed() throws {
        let model = makeModel()
        let apiClient = try file("Sources/HTTP/APIClient.swift", in: model)
        let billingGuard = try file("Sources/Billing/BillingGuard.swift", in: model)

        #expect(model.isViewed(apiClient))
        #expect(model.isCollapsed(apiClient))
        #expect(model.isViewed(billingGuard) == false)
        #expect(model.isCollapsed(billingGuard) == false)
    }

    @Test func markingViewedCollapsesTheFile() throws {
        let model = makeModel()
        let billingGuard = try file("Sources/Billing/BillingGuard.swift", in: model)

        model.toggleViewed(billingGuard)

        #expect(model.isViewed(billingGuard))
        #expect(model.isCollapsed(billingGuard))
    }

    @Test func unmarkingViewedReopensTheFile() throws {
        let model = makeModel()
        let apiClient = try file("Sources/HTTP/APIClient.swift", in: model)

        model.toggleViewed(apiClient)

        #expect(model.isViewed(apiClient) == false)
        #expect(model.isCollapsed(apiClient) == false)
    }

    @Test func collapsingByHandDoesNotMarkTheFileViewed() throws {
        let model = makeModel()
        let billingGuard = try file("Sources/Billing/BillingGuard.swift", in: model)

        model.toggleCollapsed(billingGuard)

        #expect(model.isCollapsed(billingGuard))
        #expect(model.isViewed(billingGuard) == false)

        model.toggleCollapsed(billingGuard)

        #expect(model.isCollapsed(billingGuard) == false)
    }

    // MARK: - Read hunks

    @Test func progressCountsTheHunksOfViewedFilesAsRead() {
        let model = makeModel()

        // The two files the prototype opens as viewed carry one hunk each.
        #expect(model.readHunkCount == DiffSampleData.readHunkBaseline + 2)
        #expect(model.progressText == "18 of 47 hunks read")
        #expect(model.allRead == false)
    }

    @Test func markingAHunkReadMovesTheProgress() throws {
        let model = makeModel()
        let billingGuard = try hunk("h1", in: model)

        #expect(model.isRead(billingGuard) == false)

        model.toggleRead(billingGuard)

        #expect(model.isRead(billingGuard))
        #expect(model.progressText == "19 of 47 hunks read")
    }

    @Test func unmarkingAHunkOfAViewedFileTakesTheFileOutOfViewed() throws {
        let model = makeModel()
        let apiClient = try file("Sources/HTTP/APIClient.swift", in: model)
        let apiClientHunk = try hunk("h6", in: model)

        #expect(model.isRead(apiClientHunk))

        model.toggleRead(apiClientHunk)

        #expect(model.isRead(apiClientHunk) == false)
        #expect(model.isViewed(apiClient) == false)
        #expect(model.readHunkCount == DiffSampleData.readHunkBaseline + 1)
    }

    /// Unviewed-yet-collapsed is a state the Viewed button cannot produce, so unticking
    /// a hunk must not produce it either.
    @Test func unmarkingAHunkLeavesItsFileOpenLikeUnmarkingViewedDoes() throws {
        let model = makeModel()
        let apiClient = try file("Sources/HTTP/APIClient.swift", in: model)

        model.toggleRead(try hunk("h6", in: model))

        #expect(model.isViewed(apiClient) == false)
        #expect(model.isCollapsed(apiClient) == false)
    }

    @Test func readingEveryHunkFinishesTheDiff() throws {
        let model = makeModel(readHunkBaseline: DiffSampleData.allReadHunkBaseline)

        for file in model.sectionFiles where !model.isViewed(file) {
            model.toggleViewed(file)
        }

        #expect(model.readHunkCount == DiffSampleData.totalHunkCount)
        #expect(model.progressText == "47 of 47 hunks read")
        #expect(model.progressFraction == 1)
        #expect(model.allRead)
    }

    // MARK: - Tree

    @Test func treeGroupsFilesByFolderWithDirectoriesBeforeLooseFiles() throws {
        let model = makeModel()
        let tree = model.fileTree

        let sources = try #require(tree.first?.asDirectory)
        #expect(sources.name == "Sources")
        #expect(sources.path == "Sources/")
        #expect(sources.depth == 0)

        let tests = try #require(tree.dropFirst().first?.asDirectory)
        #expect(tests.name == "Tests")

        // Package.resolved sits at the root, so it comes after every folder.
        let looseFile = try #require(tree.last?.asFile)
        #expect(looseFile.path == "Package.resolved")
        #expect(tree.last?.depth == 0)
    }

    @Test func nestedFoldersCarryTheirOwnDepth() throws {
        let model = makeModel()
        let sources = try #require(model.fileTree.first?.asDirectory)

        #expect(sources.children.compactMap(\.asDirectory).map(\.name)
            == ["API", "Billing", "HTTP", "Legacy", "Models"])

        let billing = try #require(sources.children.compactMap(\.asDirectory)
            .first { $0.name == "Billing" })
        #expect(billing.depth == 1)
        #expect(billing.path == "Sources/Billing/")
        #expect(billing.children.allSatisfy { $0.depth == 2 })
        #expect(billing.children.compactMap(\.asFile).map(\.name) == [
            "BillingConfig.swift",
            "BillingGuard.swift",
            "InvoiceScheduler.swift",
            "PlanResolver.swift",
            "ProrationCalculator.swift",
        ])
    }

    // MARK: - Filter

    @Test func filterKeepsTheAncestorFoldersOfWhatMatched() throws {
        let model = makeModel()

        model.filter = "InvoiceScheduler.swift"

        #expect(model.filteredFiles.map(\.path) == ["Sources/Billing/InvoiceScheduler.swift"])

        let tree = model.fileTree
        #expect(tree.count == 1)

        let sources = try #require(tree.first?.asDirectory)
        #expect(sources.name == "Sources")
        #expect(sources.children.count == 1)

        let billing = try #require(sources.children.first?.asDirectory)
        #expect(billing.name == "Billing")
        #expect(billing.children.compactMap(\.asFile).map(\.name) == ["InvoiceScheduler.swift"])
    }

    @Test func filterIgnoresCaseAndMatchesTheWholePath() {
        let model = makeModel()

        model.filter = "  tests/billingtests  "

        #expect(model.isFiltering)
        #expect(model.filteredFiles.count == 9)
        #expect(model.filteredFiles.allSatisfy { $0.path.hasPrefix("Tests/BillingTests/") })
    }

    @Test func emptyFilterShowsEveryFile() {
        let model = makeModel()

        model.filter = "   "

        #expect(model.isFiltering == false)
        #expect(model.filteredFiles.count == model.files.count)
    }

    @Test func foldersStartOpenAndAFilterForcesThemOpen() {
        let model = makeModel()

        #expect(model.isDirectoryOpen("Sources/Billing/"))

        model.toggleDirectory("Sources/Billing/")

        #expect(model.isDirectoryOpen("Sources/Billing/") == false)

        model.filter = "InvoiceScheduler.swift"

        #expect(model.isDirectoryOpen("Sources/Billing/"))
    }

    @Test func sidebarStartsOpenAndToggles() {
        let model = makeModel()

        #expect(model.isSidebarOpen)

        model.toggleSidebar()

        #expect(model.isSidebarOpen == false)
    }

    // MARK: - Selection

    @Test func oneSelectedLineIsNamedByItsNumber() {
        let model = makeModel()

        model.selectLines(inHunkWithID: "h1", from: 0, through: 0)

        #expect(model.selection?.location == "BillingGuard.swift:139")
        #expect(model.selection?.lineCountLabel == "1 line")
    }

    @Test func severalSelectedLinesAreNamedByTheirRange() {
        let model = makeModel()

        model.selectLines(inHunkWithID: "h3", from: 2, through: 5)

        let selection = model.selection
        #expect(selection?.location == "InvoiceScheduler.swift:202\u{2013}204")
        #expect(selection?.lineCount == 4)
        #expect(selection?.lineCountLabel == "4 lines")
    }

    @Test func aDeletionAndItsReplacementShareOneLineNumber() {
        let model = makeModel()

        model.selectLines(inHunkWithID: "h1", from: 3, through: 4)

        #expect(model.selection?.location == "BillingGuard.swift:142")
        #expect(model.selection?.lineCountLabel == "2 lines")
    }

    @Test func draggingBackwardsAndPastTheEndStillSelectsTheRun() throws {
        let model = makeModel()
        let planResolver = try hunk("h2", in: model)

        model.selectLines(inHunkWithID: "h2", from: 500, through: -3)

        #expect(model.selection?.rows == 0...(planResolver.lines.count - 1))
    }

    @Test func selectingInAnUnknownHunkClearsTheSelection() {
        let model = makeModel()
        model.selectLines(inHunkWithID: "h1", from: 0, through: 1)

        model.selectLines(inHunkWithID: "nope", from: 0, through: 1)

        #expect(model.selection == nil)
    }

    // MARK: - Chat

    @Test func aHunkWithoutAnExplanationDoesNotOpenChatAndKeepsTheActionDisabled() {
        let model = makeModel()
        let bare = DiffHunk(
            id: "bare",
            filePath: "Sources/Bare.swift",
            header: "@@ -1 +1 @@",
            location: "Bare.swift:1",
            note: nil,
            explanation: nil,
            reply: nil,
            lines: [
                DiffLine(
                    oldNumber: 1,
                    newNumber: 1,
                    kind: .context,
                    segments: [DiffLineSegment(text: "x")]
                )
            ]
        )

        #expect(model.canExplain(bare) == false)
        #expect(model.canExplainFile(DiffFile(
            path: bare.filePath,
            status: .modified,
            additions: 0,
            deletions: 0,
            hunks: [bare]
        )) == false)

        model.explain(bare)

        #expect(model.isChatOpen == false)
        #expect(model.thread == nil)
        #expect(model.pendingReply == nil)
        #expect(model.isThinking == false)
    }

    @Test func explainingAHunkThinksThenAnswersWithItsLocation() async throws {
        let model = makeModel()
        let billingGuard = try hunk("h1", in: model)

        #expect(model.canExplain(billingGuard))
        model.explain(billingGuard)

        #expect(model.isChatOpen)
        #expect(model.isThinking)
        #expect(model.thread?.messages.isEmpty == true)

        await model.pendingReply?.value

        #expect(model.isThinking == false)
        let reply = try #require(model.thread?.messages.last)
        #expect(reply.role == .agent)
        #expect(reply.text == billingGuard.explanation)
        #expect(reply.location == "BillingGuard.swift:142")
        #expect(reply.hunkID == "h1")
    }

    @Test func aNoteAnswersWithTheNoteText() async throws {
        let model = makeModel()
        let subscriptionHandler = try hunk("h4", in: model)

        model.openNote(subscriptionHandler)
        await model.pendingReply?.value

        #expect(model.thread?.messages.last?.text == subscriptionHandler.note)
    }

    @Test func aHunkWithoutANoteHasNothingToOpen() throws {
        let model = makeModel()
        let invoiceScheduler = try hunk("h3", in: model)

        model.openNote(invoiceScheduler)

        #expect(model.isChatOpen == false)
        #expect(model.thread == nil)
        #expect(model.pendingReply == nil)
    }

    @Test func explainingAFileUsesItsHunk() async throws {
        let model = makeModel()
        let planResolver = try file("Sources/Billing/PlanResolver.swift", in: model)

        model.explainFile(planResolver)
        await model.pendingReply?.value

        #expect(model.thread?.hunkID == "h2")
        #expect(model.thread?.messages.last?.text == planResolver.hunks.first?.explanation)
    }

    @Test func explainingAFileWithNoHunkOpensTheGeneralThread() async throws {
        let model = makeModel()
        let billingConfig = try file("Sources/Billing/BillingConfig.swift", in: model)

        model.explainFile(billingConfig)

        #expect(model.isChatOpen)
        #expect(model.thread?.messages.map(\.text) == [DiffSampleData.openingAgentMessage])
        #expect(model.pendingReply == nil)
    }

    @Test func theHunkAnswersTheFirstFollowUpAndThenRunsOut() async throws {
        let model = makeModel()
        let billingGuard = try hunk("h1", in: model)
        model.explain(billingGuard)
        await model.pendingReply?.value

        model.send("Was that intentional?")

        #expect(model.thread?.messages.last?.role == .user)
        #expect(model.isThinking)

        await model.pendingReply?.value

        #expect(model.thread?.messages.last?.text == billingGuard.reply)

        model.send("And the pricing copy?")
        await model.pendingReply?.value

        #expect(model.thread?.messages.last?.text == DiffSampleData.fallbackReply)
    }

    @Test func aQuestionWithNoThreadIsAnchoredToTheBranchPair() async throws {
        let model = makeModel()

        model.send("  What changed in billing?  ")

        #expect(model.thread?.location == "feature/annual-billing → main")
        let question = try #require(model.thread?.messages.first)
        #expect(question.role == .user)
        #expect(question.text == "What changed in billing?")
        #expect(question.location == nil)

        await model.pendingReply?.value

        #expect(model.thread?.messages.last?.text == DiffSampleData.fallbackReply)
    }

    @Test func anEmptyQuestionIsNotSent() {
        let model = makeModel()

        model.send("   ")

        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)
    }

    @Test func explainingASelectionCarriesItsLocationAndCount() async throws {
        let model = makeModel()
        model.selectLines(inHunkWithID: "h3", from: 2, through: 5)

        model.explainSelection()

        #expect(model.selection == nil)
        #expect(model.isChatOpen)
        #expect(model.isThinking)

        await model.pendingReply?.value

        let reply = try #require(model.thread?.messages.last)
        #expect(reply.text == DiffSampleData.explainSelectionReply(lineCountLabel: "4 lines"))
        #expect(reply.location == "InvoiceScheduler.swift:202\u{2013}204")
        #expect(reply.hunkID == nil)
    }

    @Test func askingAboutASelectionSendsTheQuestionWithItsChip() async throws {
        let model = makeModel()
        model.selectLines(inHunkWithID: "h3", from: 2, through: 5)

        model.askAboutSelection("Does WebhookSender catch it?")

        let question = try #require(model.thread?.messages.last)
        #expect(question.role == .user)
        #expect(question.text == "Does WebhookSender catch it?")
        #expect(question.location == "InvoiceScheduler.swift:202\u{2013}204")
        #expect(model.selection == nil)

        await model.pendingReply?.value

        #expect(model.thread?.messages.last?.text == DiffSampleData.selectionQuestionReply(
            location: "InvoiceScheduler.swift:202\u{2013}204",
            question: "Does WebhookSender catch it?"
        ))
    }

    @Test func askingNothingAboutASelectionExplainsItInstead() async throws {
        let model = makeModel()
        model.selectLines(inHunkWithID: "h1", from: 0, through: 0)

        model.askAboutSelection("   ")
        await model.pendingReply?.value

        #expect(model.thread?.messages.map(\.role) == [.agent])
        #expect(model.thread?.messages.last?.text
            == DiffSampleData.explainSelectionReply(lineCountLabel: "1 line"))
    }

    @Test func openingTheChatWithNoHunkIntroducesTheAgentOnce() {
        let model = makeModel()

        model.openChat()
        model.closeChat()
        model.openChat()

        #expect(model.isChatOpen)
        #expect(model.thread?.messages.map(\.text) == [DiffSampleData.openingAgentMessage])
    }

    @Test func theChatDefaultsToOpusFiveOnHighReasoning() {
        let model = makeModel()

        #expect(model.chatModel == .opus5)
        #expect(model.chatModel.title == "Opus 5")
        #expect(model.reasoningEffort == .high)
        #expect(model.reasoningEffort.title == "High")
    }

    // MARK: - Leaving

    @Test func goingBackToWelcomeDropsTheReadingAndTheConversation() async throws {
        let model = makeModel()
        let billingGuard = try file("Sources/Billing/BillingGuard.swift", in: model)
        let apiClient = try file("Sources/HTTP/APIClient.swift", in: model)
        model.toggleViewed(billingGuard)
        model.toggleViewed(apiClient)
        model.toggleRead(try hunk("h2", in: model))
        model.selectLines(inHunkWithID: "h1", from: 0, through: 1)
        model.explain(try hunk("h1", in: model))
        await model.pendingReply?.value

        model.returnToWelcome()

        #expect(model.viewedPaths == DiffSampleData.defaultViewedPaths)
        #expect(model.isViewed(apiClient))
        #expect(model.isCollapsed(apiClient))
        #expect(model.isViewed(billingGuard) == false)
        #expect(model.readHunkIDs.isEmpty)
        #expect(model.readHunkCount == DiffSampleData.readHunkBaseline + 2)
        #expect(model.selection == nil)
        #expect(model.thread == nil)
        #expect(model.isChatOpen == false)
        #expect(model.isThinking == false)
    }

    @Test func theHunkReplyIsAvailableAgainAfterComingBack() async throws {
        let model = makeModel()
        let billingGuard = try hunk("h1", in: model)
        model.explain(billingGuard)
        await model.pendingReply?.value
        model.send("Was that intentional?")
        await model.pendingReply?.value

        model.returnToWelcome()
        model.explain(billingGuard)
        await model.pendingReply?.value
        model.send("Was that intentional?")
        await model.pendingReply?.value

        #expect(model.thread?.messages.last?.text == billingGuard.reply)
    }

    // MARK: - Thinking indicator

    @Test func theThinkingIndicatorCyclesGlyphsAndWords() throws {
        let indicator = try #require(makeModel().thinkingIndicator)

        #expect(indicator.glyph(step: 0) == "⠋")
        #expect(indicator.glyph(step: 1) == "⠙")
        #expect(indicator.glyph(step: 10) == "⠋")

        #expect(indicator.word(step: 0) == "Thinking")
        #expect(indicator.word(step: 5) == "Thinking")
        #expect(indicator.word(step: 6) == "Reading the hunk")
        #expect(indicator.word(step: 24) == "Thinking")
    }

    // MARK: - Sample data

    @Test func theSampleIsPresentedAsPartOfALargerDiff() {
        let model = makeModel()

        #expect(model.files.count == 31)
        #expect(model.sectionFiles.count == 8)
        #expect(DiffSampleData.declaredFileCount == 64)
        #expect(model.totalHunkCount == 47)
    }

    @Test func fileRowsReadTheirPathApart() throws {
        let model = makeModel()
        let subscription = try file("Sources/Models/Subscription.swift", in: model)
        let packageResolved = try file("Package.resolved", in: model)
        let snapshot = try file("Tests/__Snapshots__/InvoiceView@2x.png", in: model)

        #expect(subscription.name == "Subscription.swift")
        #expect(subscription.directory == "Sources/Models/")
        #expect(subscription.status.title == "Modified")
        #expect(subscription.additionsLabel == "+3")
        #expect(subscription.deletionsLabel == "\u{2212}1")

        #expect(packageResolved.directory.isEmpty)
        #expect(packageResolved.name == "Package.resolved")

        // A binary file changed on both sides shows no counters at all.
        #expect(snapshot.additionsLabel.isEmpty)
        #expect(snapshot.deletionsLabel.isEmpty)
    }
}
