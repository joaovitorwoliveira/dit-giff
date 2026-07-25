import Observation

/// State of the Welcome screen. Every rule about what a selection implies lives here,
/// so the view stays a rendering of this object and nothing else.
@MainActor
@Observable
final class WelcomeModel {
    private(set) var selectedRepository: WelcomeRepository?
    var compareBranch: String?
    var baseBranch = WelcomeSampleData.defaultBaseBranch
    var goal = ""
    private(set) var attachedSpecName: String?

    var canOpenDiff: Bool { compareBranch != nil }

    var changeSummary: String {
        guard let compareBranch else { return WelcomeSampleData.unknownChangeSummary }
        return WelcomeSampleData.changeSummary(forBranch: compareBranch)
    }

    func select(_ repository: WelcomeRepository) {
        selectedRepository = repository
        compareBranch = WelcomeSampleData.preselectedCompareBranch(for: repository)
    }

    /// The prototype has no file dialog; "Open repository…" stands in for one.
    func selectFirstRepository() {
        guard let first = WelcomeSampleData.repositories.first else { return }
        select(first)
    }

    /// A goal written for one change does not describe another, so going back drops it.
    func clearRepository() {
        selectedRepository = nil
        compareBranch = nil
        goal = ""
        attachedSpecName = nil
    }

    func attachSpec() {
        attachedSpecName = WelcomeSampleData.sampleSpecName
    }

    func removeSpec() {
        attachedSpecName = nil
    }
}
