/// What's still fake on Welcome — and only that.
///
/// Repositories, branches and change counts come from git (Slice 2). Goal text and the
/// attached `.md` spec are prompt context; they stay mocked until Slice 5 (contexto e
/// prompt). This is the last Welcome mock on purpose.
enum WelcomeSampleData {
    static let sampleSpecName = "annual-billing-spec.md"

    static let compareBranchPlaceholder = "Choose a branch…"

    /// An em dash: unknown and empty are different from a real zero.
    static let unknownChangeSummary = "—"

    /// Shown while the selected pair's file count is in flight — never a premature "0".
    static let countingChangeSummary = "Counting…"
}
