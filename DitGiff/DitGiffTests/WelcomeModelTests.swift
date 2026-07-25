import Testing

@testable import DitGiff

@MainActor
struct WelcomeModelTests {
    private func repository(named name: String) throws -> WelcomeRepository {
        try #require(WelcomeSampleData.repositories.first { $0.name == name })
    }

    @Test func cannotOpenDiffWithoutRepository() {
        let model = WelcomeModel()

        #expect(model.canOpenDiff == false)
    }

    @Test func cannotOpenDiffWithRepositoryButNoCompareBranch() throws {
        let model = WelcomeModel()

        let ditGiff = try repository(named: "dit-giff")

        model.select(ditGiff)

        #expect(model.compareBranch == nil)
        #expect(model.canOpenDiff == false)
    }

    @Test func canOpenDiffOnceCompareBranchIsChosen() {
        let model = WelcomeModel()

        model.compareBranch = "develop"

        #expect(model.canOpenDiff)
    }

    @Test func selectingRepositoryPreselectsItsCurrentBranch() throws {
        let model = WelcomeModel()
        let billing = try repository(named: "billing-service")

        model.select(billing)

        #expect(model.selectedRepository == billing)
        #expect(model.compareBranch == "feature/annual-billing")
    }

    @Test func selectingRepositoryOnBaseBranchLeavesCompareUnselected() throws {
        let model = WelcomeModel()
        let ditGiff = try repository(named: "dit-giff")

        model.select(ditGiff)

        #expect(ditGiff.currentBranch == WelcomeSampleData.defaultBaseBranch)
        #expect(model.compareBranch == nil)
    }

    @Test func clearingRepositoryResetsCompareBranchGoalAndSpec() throws {
        let model = WelcomeModel()
        let metrics = try repository(named: "swift-metrics")
        model.select(metrics)
        model.goal = "Stop double-charging annual plans."
        model.attachSpec()

        model.clearRepository()

        #expect(model.selectedRepository == nil)
        #expect(model.compareBranch == nil)
        #expect(model.goal.isEmpty)
        #expect(model.attachedSpecName == nil)
    }

    @Test func changeSummaryReportsSampleCountForKnownBranch() {
        let model = WelcomeModel()

        model.compareBranch = "feature/annual-billing"

        #expect(model.changeSummary == "64 files · +3242 −347")
    }

    @Test func changeSummaryIsUnknownForBranchWithoutSampleCount() {
        let model = WelcomeModel()

        model.compareBranch = "feature/not-in-the-sample"

        #expect(model.changeSummary == WelcomeSampleData.unknownChangeSummary)
    }
}
