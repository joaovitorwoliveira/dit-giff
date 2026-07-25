import Testing

@testable import DitGiff

@MainActor
struct DiffFileNavigationTests {
    private func makeModel() -> DiffModel {
        DiffModel(replyDelay: ImmediateReplyDelay(), readHunkBaseline: DiffSampleData.readHunkBaseline)
    }

    // MARK: - Resolver

    @Test func scrollAnchorIDIsStableAndPathScoped() {
        #expect(
            DiffFileNavigationResolver.scrollAnchorID(filePath: "Sources/A.swift")
                == "diff-file:Sources/A.swift"
        )
        #expect(
            DiffFileNavigationResolver.scrollAnchorID(filePath: "Sources/A.swift")
                != DiffFileNavigationResolver.scrollAnchorID(filePath: "Sources/B.swift")
        )
    }

    @Test func resolveScrollsWhenTheFileIsInTheReader() {
        let result = DiffFileNavigationResolver.resolve(
            filePath: "Sources/Billing/BillingGuard.swift",
            sectionFilePaths: ["Sources/Billing/BillingGuard.swift", "Sources/HTTP/APIClient.swift"]
        )

        #expect(result == .scrollToHeader(path: "Sources/Billing/BillingGuard.swift"))
    }

    @Test func resolveMarksUnavailableWhenTheFileHasNoHunksInTheReader() {
        let result = DiffFileNavigationResolver.resolve(
            filePath: "Sources/Billing/BillingConfig.swift",
            sectionFilePaths: ["Sources/Billing/BillingGuard.swift"]
        )

        #expect(result == .unavailableInReader(path: "Sources/Billing/BillingConfig.swift"))
    }

    @Test func navigationDoesNotExpandCollapsedFiles() {
        #expect(DiffFileNavigationResolver.expandsCollapsedFileOnNavigate == false)
    }

    // MARK: - Model

    @Test func revealingASectionFileRequestsATopAnchoredScrollAndFocusesIt() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        #expect(model.sectionFiles.contains(where: { $0.path == billingGuard.path }))

        model.revealFileInReader(billingGuard)

        #expect(model.isFocusedInSidebar(billingGuard))
        #expect(model.focusedFilePath == billingGuard.path)
        let request = try #require(model.readerScrollRequest)
        #expect(request.path == billingGuard.path)
        #expect(
            DiffFileNavigationResolver.scrollAnchorID(filePath: request.path)
                == "diff-file:Sources/Billing/BillingGuard.swift"
        )
    }

    @Test func revealingTheSameFileAgainIssuesANewScrollRequest() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )

        model.revealFileInReader(billingGuard)
        let first = try #require(model.readerScrollRequest)
        model.clearReaderScrollRequest()
        #expect(model.readerScrollRequest == nil)

        model.revealFileInReader(billingGuard)
        let second = try #require(model.readerScrollRequest)

        #expect(second.path == first.path)
        #expect(second.nonce != first.nonce)
    }

    @Test func revealingAFileWithoutHunksFocusesButDoesNotScroll() throws {
        let model = makeModel()
        let billingConfig = try #require(
            model.file(atPath: "Sources/Billing/BillingConfig.swift")
        )
        #expect(billingConfig.hunks.isEmpty)
        #expect(model.sectionFiles.contains(where: { $0.path == billingConfig.path }) == false)

        model.revealFileInReader(billingConfig)

        #expect(model.isFocusedInSidebar(billingConfig))
        #expect(model.readerScrollRequest == nil)
    }

    @Test func revealingACollapsedFileKeepsItCollapsedAndStillScrollsToItsHeader() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.toggleCollapsed(billingGuard)
        #expect(model.isCollapsed(billingGuard))

        model.revealFileInReader(billingGuard)

        #expect(model.isCollapsed(billingGuard))
        #expect(model.readerScrollRequest?.path == billingGuard.path)
        #expect(DiffFileNavigationResolver.expandsCollapsedFileOnNavigate == false)
    }

    @Test func clearingAScrollRequestLeavesFocusInPlace() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)

        model.clearReaderScrollRequest()

        #expect(model.readerScrollRequest == nil)
        #expect(model.isFocusedInSidebar(billingGuard))
    }

    @Test func returningToWelcomeClearsFocusAndPendingScroll() throws {
        let model = makeModel()
        let billingGuard = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        model.revealFileInReader(billingGuard)

        model.returnToWelcome()

        #expect(model.focusedFilePath == nil)
        #expect(model.readerScrollRequest == nil)
    }
}

private struct ImmediateReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}
