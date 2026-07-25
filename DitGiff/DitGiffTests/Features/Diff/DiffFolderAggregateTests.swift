import Testing

@testable import DitGiff

private extension DiffTreeNode {
    var asDirectory: DiffTreeDirectory? {
        guard case let .directory(directory) = self else { return nil }
        return directory
    }
}

private extension [DiffTreeNode] {
    func directory(atPath path: String) -> DiffTreeDirectory? {
        for node in self {
            guard let directory = node.asDirectory else { continue }
            if directory.path == path { return directory }
            if let nested = directory.children.directory(atPath: path) {
                return nested
            }
        }
        return nil
    }
}

@MainActor
struct DiffFolderAggregateTests {
    private func makeModel() -> DiffModel {
        DiffModel(replyDelay: ImmediateFolderReplyDelay(), readHunkBaseline: DiffSampleData.readHunkBaseline)
    }

    private func directory(_ path: String, in model: DiffModel) throws -> DiffTreeDirectory {
        try #require(model.fileTree.directory(atPath: path))
    }

    // MARK: - Collecting descendants

    @Test func descendantFilesIncludeNestedSubfoldersAtAnyDepth() {
        let leaf = DiffFile(
            path: "a/b/c/Deep.swift",
            status: .modified,
            additions: 1,
            deletions: 0,
            hunks: []
        )
        let mid = DiffFile(
            path: "a/b/Mid.swift",
            status: .modified,
            additions: 1,
            deletions: 0,
            hunks: []
        )
        let deep = DiffTreeDirectory(
            path: "a/b/c/",
            name: "c",
            depth: 2,
            children: [.file(leaf, depth: 3)]
        )
        let nested = DiffTreeDirectory(
            path: "a/b/",
            name: "b",
            depth: 1,
            children: [
                .directory(deep),
                .file(mid, depth: 2),
            ]
        )
        let root = DiffTreeDirectory(
            path: "a/",
            name: "a",
            depth: 0,
            children: [.directory(nested)]
        )

        #expect(root.descendantFiles.map(\.path) == [
            "a/b/c/Deep.swift",
            "a/b/Mid.swift",
        ])
        #expect(nested.descendantFiles.map(\.path) == [
            "a/b/c/Deep.swift",
            "a/b/Mid.swift",
        ])
        #expect(deep.descendantFiles.map(\.path) == ["a/b/c/Deep.swift"])
    }

    @Test func sampleSourcesFolderCollectsEveryFileUnderNestedChildren() throws {
        let model = makeModel()
        let sources = try directory("Sources/", in: model)
        let paths = Set(sources.descendantFiles.map(\.path))

        #expect(paths.contains("Sources/Billing/BillingGuard.swift"))
        #expect(paths.contains("Sources/HTTP/APIClient.swift"))
        #expect(paths.contains("Sources/API/SubscriptionHandler.swift"))
        #expect(paths.contains("Sources/Models/Subscription.swift"))
        #expect(paths.contains("Package.resolved") == false)
        #expect(paths.contains("Tests/BillingTests/AnnualBillingTests.swift") == false)
    }

    // MARK: - Aggregate state

    @Test func aggregateStateCoversNoneSomeAndAll() {
        #expect(DiffAggregateState.of(matchingCount: 0, total: 5) == .none)
        #expect(DiffAggregateState.of(matchingCount: 2, total: 5) == .some)
        #expect(DiffAggregateState.of(matchingCount: 5, total: 5) == .all)
        #expect(DiffAggregateState.of(matchingCount: 0, total: 0) == .none)
        #expect(DiffAggregateState.none.togglesTowardAll)
        #expect(DiffAggregateState.some.togglesTowardAll)
        #expect(DiffAggregateState.all.togglesTowardAll == false)
    }

    @Test func viewedStateIsNoneSomeOrAllAcrossAFolder() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        let http = try directory("Sources/HTTP/", in: model)

        #expect(model.viewedState(for: billing) == .none)
        #expect(model.viewedState(for: http) == .some)

        for file in billing.descendantFiles {
            model.toggleViewed(file)
        }
        #expect(model.viewedState(for: billing) == .all)
    }

    @Test func nestedFolderReflectsADeepDescendantNotOnlyDirectChildren() throws {
        let model = makeModel()
        let sources = try directory("Sources/", in: model)
        let billingGuard = try #require(model.file(atPath: "Sources/Billing/BillingGuard.swift"))

        // Sources has a direct child that is already viewed (APIClient under HTTP), so the
        // folder starts partial. Clearing every descendant first isolates the deep mark.
        model.toggleViewed(in: sources)
        model.toggleViewed(in: sources)
        #expect(model.viewedState(for: sources) == .none)

        model.toggleViewed(billingGuard)

        #expect(model.viewedState(for: sources) == .some)
        #expect(model.isViewed(billingGuard))
    }

    // MARK: - Click rules

    @Test func clickingPartialViewedMarksEveryDescendant() throws {
        let model = makeModel()
        let http = try directory("Sources/HTTP/", in: model)
        #expect(model.viewedState(for: http) == .some)

        model.toggleViewed(in: http)

        #expect(model.viewedState(for: http) == .all)
        #expect(http.descendantFiles.allSatisfy(model.isViewed))
        #expect(http.descendantFiles.allSatisfy(model.isCollapsed))
    }

    @Test func clickingAllViewedClearsEveryDescendant() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        model.toggleViewed(in: billing)
        #expect(model.viewedState(for: billing) == .all)

        model.toggleViewed(in: billing)

        #expect(model.viewedState(for: billing) == .none)
        #expect(billing.descendantFiles.allSatisfy { !model.isViewed($0) })
        #expect(billing.descendantFiles.allSatisfy { !model.isCollapsed($0) })
    }

    @Test func clickingPartialCollapsedCollapsesEveryDescendant() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        let first = try #require(billing.descendantFiles.first)
        model.toggleCollapsed(first)
        #expect(model.collapsedState(for: billing) == .some)

        model.toggleCollapsed(in: billing)

        #expect(model.collapsedState(for: billing) == .all)
        #expect(billing.descendantFiles.allSatisfy(model.isCollapsed))
        #expect(billing.descendantFiles.allSatisfy { !model.isViewed($0) })
    }

    @Test func clickingAllCollapsedExpandsEveryDescendant() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        model.toggleCollapsed(in: billing)
        #expect(model.collapsedState(for: billing) == .all)

        model.toggleCollapsed(in: billing)

        #expect(model.collapsedState(for: billing) == .none)
        #expect(billing.descendantFiles.allSatisfy { !model.isCollapsed($0) })
    }

    // MARK: - Reader ↔ sidebar sync and dimming

    @Test func markingViewedInTheReaderDimsTheFileInTheSidebar() throws {
        let model = makeModel()
        let billingGuard = try #require(model.file(atPath: "Sources/Billing/BillingGuard.swift"))
        #expect(model.isDimmedInSidebar(billingGuard) == false)

        // Same API the reader header uses.
        model.toggleViewed(billingGuard)

        #expect(model.isViewed(billingGuard))
        #expect(model.isDimmedInSidebar(billingGuard))
        #expect(model.viewedState(for: try directory("Sources/Billing/", in: model)) == .some)
    }

    @Test func markingViewedInTheSidebarReflectsOnTheReaderFile() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        let billingGuard = try #require(model.file(atPath: "Sources/Billing/BillingGuard.swift"))

        model.toggleViewed(in: billing)

        #expect(model.isViewed(billingGuard))
        #expect(model.isCollapsed(billingGuard))
        #expect(model.isDimmedInSidebar(billingGuard))
    }

    @Test func folderIsDimmedOnlyWhenEveryDescendantIsViewed() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        let http = try directory("Sources/HTTP/", in: model)

        #expect(model.isDimmedInSidebar(billing) == false)
        #expect(model.viewedState(for: http) == .some)
        #expect(model.isDimmedInSidebar(http) == false)

        model.toggleViewed(in: billing)

        #expect(model.viewedState(for: billing) == .all)
        #expect(model.isDimmedInSidebar(billing))
    }

    @Test func dimmingLookupsDoNotRescanDescendantsPerRow() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        let before = model.directoryViewedStateRefreshCount

        // Many O(1) reads must not rebuild the aggregate map.
        for _ in 0..<billing.descendantFiles.count {
            _ = model.isDimmedInSidebar(billing)
            _ = model.viewedState(for: billing)
        }

        #expect(model.directoryViewedStateRefreshCount == before)
    }

    // MARK: - Batch cache invalidation

    @Test func batchViewedToggleRefreshesProgressOnceAndLeavesTheTreeCacheAlone() throws {
        let model = makeModel()
        let sources = try directory("Sources/", in: model)
        let progressBefore = model.readProgressRefreshCount
        let filterBefore = model.filterCacheRefreshCount
        let viewedBefore = model.directoryViewedStateRefreshCount
        let treeBefore = model.fileTree

        model.toggleViewed(in: sources)

        #expect(model.readProgressRefreshCount == progressBefore + 1)
        #expect(model.directoryViewedStateRefreshCount == viewedBefore + 1)
        #expect(model.filterCacheRefreshCount == filterBefore)
        #expect(model.fileTree == treeBefore)
        #expect(model.viewedState(for: sources) == .all)
    }

    @Test func batchViewedToggleDoesNotRefreshProgressOncePerFile() throws {
        let model = makeModel()
        let billing = try directory("Sources/Billing/", in: model)
        let fileCount = billing.descendantFiles.count
        #expect(fileCount > 1)
        let progressBefore = model.readProgressRefreshCount
        let viewedBefore = model.directoryViewedStateRefreshCount

        model.toggleViewed(in: billing)

        #expect(model.readProgressRefreshCount == progressBefore + 1)
        #expect(model.directoryViewedStateRefreshCount == viewedBefore + 1)
        #expect(model.readProgressRefreshCount != progressBefore + fileCount)
        #expect(model.directoryViewedStateRefreshCount != viewedBefore + fileCount)
    }

    @Test func batchCollapsedToggleDoesNotTouchProgressOrTreeCaches() throws {
        let model = makeModel()
        let sources = try directory("Sources/", in: model)
        let progressBefore = model.readProgressRefreshCount
        let filterBefore = model.filterCacheRefreshCount
        let viewedBefore = model.directoryViewedStateRefreshCount

        model.toggleCollapsed(in: sources)

        #expect(model.readProgressRefreshCount == progressBefore)
        #expect(model.filterCacheRefreshCount == filterBefore)
        #expect(model.directoryViewedStateRefreshCount == viewedBefore)
        #expect(model.collapsedState(for: sources) == .all)
    }
}

/// Same seam DiffModelTests uses — kept local so this file stays self-contained.
private struct ImmediateFolderReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}
