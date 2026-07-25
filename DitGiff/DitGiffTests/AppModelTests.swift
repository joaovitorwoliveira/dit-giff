import SwiftUI
import Testing

@testable import DitGiff

@MainActor
struct AppModelTests {
    // MARK: - Route

    @Test func theWindowOpensOnWelcome() {
        let model = AppModel()

        #expect(model.route == .welcome)
    }

    @Test func openingAndLeavingTheDiffMovesTheRouteBothWays() {
        let model = AppModel()
        let session = Self.sampleSession

        model.openDiff(session)

        #expect(model.route == .diff)
        #expect(model.activeDiffSession == session)

        model.returnToWelcome()

        #expect(model.route == .welcome)
    }

    // MARK: - Theme

    @Test func theThemeFollowsTheSystemUntilItIsPicked() {
        let model = AppModel()

        #expect(model.themeOverride == nil)
    }

    @Test func theFirstToggleFlipsWhateverTheSystemWasShowing() {
        let fromDark = AppModel()
        let fromLight = AppModel()

        fromDark.toggleTheme(from: .dark)
        fromLight.toggleTheme(from: .light)

        #expect(fromDark.themeOverride == .light)
        #expect(fromLight.themeOverride == .dark)
    }

    /// Once a side is picked, the system's own scheme stops having a say.
    @Test func laterTogglesFlipThePickAndIgnoreTheSystem() {
        let model = AppModel()
        model.toggleTheme(from: .dark)

        model.toggleTheme(from: .dark)

        #expect(model.themeOverride == .dark)

        model.toggleTheme(from: .light)

        #expect(model.themeOverride == .light)
    }

    @Test func thePickedThemeSurvivesNavigation() {
        let model = AppModel()
        model.toggleTheme(from: .dark)

        model.openDiff(Self.sampleSession)
        model.returnToWelcome()

        #expect(model.themeOverride == .light)
    }

    // MARK: - The diff session

    @Test func leavingTheDiffEndsTheReadingSession() throws {
        let diffModel = DiffModel()
        let model = AppModel(welcomeModel: AppModel().welcomeModel, diffModel: diffModel)
        model.openDiff(Self.sampleSession)
        let billingGuard = try #require(diffModel.file(atPath: "Sources/Billing/BillingGuard.swift"))
        diffModel.toggleViewed(billingGuard)
        diffModel.toggleRead(try #require(diffModel.hunk(withID: "h2")))

        model.returnToWelcome()

        #expect(diffModel.readHunkIDs.isEmpty)
        #expect(diffModel.viewedPaths == DiffSampleData.defaultViewedPaths)
        #expect(diffModel.isViewed(billingGuard) == false)
        #expect(model.route == .welcome)
    }

    /// How this person works is not what they are reading: the sidebar and the chat's
    /// settings are theirs to keep across a trip back to Welcome.
    @Test func leavingTheDiffKeepsTheWorkspaceSettings() {
        let diffModel = DiffModel()
        let model = AppModel(welcomeModel: AppModel().welcomeModel, diffModel: diffModel)
        model.openDiff(Self.sampleSession)
        diffModel.toggleSidebar()
        diffModel.filter = "billing"
        diffModel.reasoningEffort = .max

        model.returnToWelcome()
        model.openDiff(Self.sampleSession)

        #expect(diffModel.isSidebarOpen == false)
        #expect(diffModel.filter == "billing")
        #expect(diffModel.reasoningEffort == .max)
    }

    @Test func theDiffSessionIsTheSameObjectAcrossOpenings() {
        let diffModel = DiffModel()
        let model = AppModel(welcomeModel: AppModel().welcomeModel, diffModel: diffModel)

        model.openDiff(Self.sampleSession)
        model.returnToWelcome()
        model.openDiff(Self.sampleSession)

        #expect(model.diffModel === diffModel)
    }

    @Test func welcomeModelSurvivesATripToTheDiffAndBack() {
        let model = AppModel()
        let welcome = model.welcomeModel

        model.openDiff(Self.sampleSession)
        model.returnToWelcome()

        #expect(model.welcomeModel === welcome)
    }

    private static var sampleSession: DiffSession {
        let repository = GitRepository(
            rootURL: URL(fileURLWithPath: "/tmp/sample", isDirectory: true),
            displayName: "sample",
            head: .branch("feature")
        )
        return DiffSession(
            repository: repository,
            base: GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil),
            compare: GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil),
            goal: "",
            attachedSpecName: nil
        )
    }
}
