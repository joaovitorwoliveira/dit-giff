import Observation
import SwiftUI

enum AppRoute: Equatable, Sendable {
    case welcome
    case diff
}

/// What survives navigation: which screen is up, which theme was picked, the Welcome
/// setup, and the diff session itself.
@MainActor
@Observable
final class AppModel {
    private(set) var route: AppRoute = .welcome
    /// `nil` follows the OS. Once the reader picks a side, the pick stands.
    private(set) var themeOverride: ColorScheme?

    /// Lives here so returning from the diff does not wipe repository and branch picks.
    let welcomeModel: WelcomeModel

    /// One session for the life of the window, rather than a fresh model per opening.
    /// Reading state has to end when the reader leaves — `returnToWelcome()` is what ends
    /// it — but the filter, the sidebar and the chat's model and effort are how this
    /// person works, not what they are reading, and rebuilding the model would throw
    /// those away every time. Slice 6's "where I left off" wants the same object anyway.
    let diffModel: DiffModel

    /// Set when the reader opens the diff. Drives the real patch load on `DiffModel`.
    private(set) var activeDiffSession: DiffSession?

    init(welcomeModel: WelcomeModel, diffModel: DiffModel) {
        self.welcomeModel = welcomeModel
        self.diffModel = diffModel
    }

    /// Composition root: real process runner, git service, and Application Support store.
    convenience init() {
        let runner = SystemCommandRunner()
        let git = GitService(runner: runner)
        let store: RecentRepositoriesStore
        do {
            store = try RecentRepositoriesStore()
        } catch {
            preconditionFailure("Could not create Application Support for DitGiff: \(error)")
        }
        self.init(
            welcomeModel: WelcomeModel(
                git: git,
                recentStore: store,
                directoryPicker: SystemDirectoryPicker()
            ),
            diffModel: DiffModel(git: git)
        )
    }

    func openDiff(_ session: DiffSession) {
        activeDiffSession = session
        route = .diff
        diffModel.load(session)
    }

    /// Leaving the diff ends the reading session. Routing and resetting are one call so
    /// no screen can navigate away and leave the last read behind.
    func returnToWelcome() {
        diffModel.returnToWelcome()
        activeDiffSession = nil
        route = .welcome
    }

    /// Coming from "follow the OS", the toggle has to know what is actually on screen —
    /// only the view can say. After that the override answers for itself.
    func toggleTheme(from currentScheme: ColorScheme) {
        themeOverride = (themeOverride ?? currentScheme) == .dark ? .light : .dark
    }
}
