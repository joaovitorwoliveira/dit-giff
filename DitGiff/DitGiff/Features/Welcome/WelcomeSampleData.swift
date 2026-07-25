struct WelcomeRepository: Identifiable, Equatable, Sendable {
    let name: String
    let path: String
    let currentBranch: String

    var id: String { path }
}

/// Stand-in for real git while the Welcome screen is a static prototype.
/// Values are lifted from `docs/design-handoff/Dit Giff v2.dc.html`.
enum WelcomeSampleData {
    static let repositories: [WelcomeRepository] = [
        WelcomeRepository(
            name: "billing-service",
            path: "~/Code/billing-service",
            currentBranch: "feature/annual-billing"
        ),
        WelcomeRepository(
            name: "dit-giff",
            path: "~/Code/dit-giff",
            currentBranch: "main"
        ),
        WelcomeRepository(
            name: "swift-metrics",
            path: "~/OSS/swift-metrics",
            currentBranch: "develop"
        ),
    ]

    static let compareBranches = [
        "feature/annual-billing",
        "feature/http-migration",
        "fix/decimal-rounding",
        "develop",
    ]

    static let baseBranches = ["main", "develop", "master"]

    static let defaultBaseBranch = "main"

    static let compareBranchPlaceholder = "Choose a branch…"

    static let sampleSpecName = "annual-billing-spec.md"

    /// An em dash, not "0 files": unknown and empty are different things.
    static let unknownChangeSummary = "—"

    private static let changeSummaries = [
        "feature/annual-billing": "64 files · +3242 −347",
        "feature/http-migration": "31 files · +1180 −904",
        "fix/decimal-rounding": "3 files · +41 −12",
        "develop": "112 files · +5820 −3311",
    ]

    static func changeSummary(forBranch branch: String) -> String {
        changeSummaries[branch] ?? unknownChangeSummary
    }

    /// Preselect the branch the repository is already on, unless that is the default
    /// base — comparing a branch to itself is not a diff.
    static func preselectedCompareBranch(for repository: WelcomeRepository) -> String? {
        repository.currentBranch == defaultBaseBranch ? nil : repository.currentBranch
    }
}
