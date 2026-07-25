import Observation
import SwiftUI

enum AppRoute: Equatable, Sendable {
    case welcome
    case diff
}

/// What survives navigation: which screen is up, which theme was picked, and the diff
/// session itself.
@MainActor
@Observable
final class AppModel {
    private(set) var route: AppRoute = .welcome
    /// `nil` follows the OS. Once the reader picks a side, the pick stands.
    private(set) var themeOverride: ColorScheme?

    /// One session for the life of the window, rather than a fresh model per opening.
    /// Reading state has to end when the reader leaves — `returnToWelcome()` is what ends
    /// it — but the filter, the sidebar and the chat's model and effort are how this
    /// person works, not what they are reading, and rebuilding the model would throw
    /// those away every time. Slice 4's "where I left off" wants the same object anyway.
    let diffModel: DiffModel

    init(diffModel: DiffModel) {
        self.diffModel = diffModel
    }

    // A default argument would be built outside the main actor, which `DiffModel` is not
    // available from.
    convenience init() {
        self.init(diffModel: DiffModel())
    }

    func openDiff() {
        route = .diff
    }

    /// Leaving the diff ends the reading session. Routing and resetting are one call so
    /// no screen can navigate away and leave the last read behind.
    func returnToWelcome() {
        diffModel.returnToWelcome()
        route = .welcome
    }

    /// Coming from "follow the OS", the toggle has to know what is actually on screen —
    /// only the view can say. After that the override answers for itself.
    func toggleTheme(from currentScheme: ColorScheme) {
        themeOverride = (themeOverride ?? currentScheme) == .dark ? .light : .dark
    }
}
