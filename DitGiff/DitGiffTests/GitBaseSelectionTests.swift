import Foundation
import Testing

@testable import DitGiff

nonisolated struct GitBaseSelectionTests {

    private func local(_ name: String) -> GitBranch {
        GitBranch(name: name, fullRef: "refs/heads/\(name)", remote: nil)
    }

    private func remote(_ remote: String, _ name: String) -> GitBranch {
        GitBranch(
            name: name,
            fullRef: "refs/remotes/\(remote)/\(name)",
            remote: remote
        )
    }

    @Test func prefersOriginHEADWhenPresent() {
        let branches = [
            local("feature"),
            local("main"),
            remote("origin", "main"),
            remote("origin", "develop"),
        ]

        let base = GitBaseSelection.probableBase(
            among: branches,
            originHEADRef: "refs/remotes/origin/develop",
            currentBranchName: "feature"
        )

        #expect(base == remote("origin", "develop"))
    }

    @Test func fallsBackToMainThenDevelopThenMaster() {
        let withDevelop = [local("feature"), local("develop"), remote("origin", "develop")]
        #expect(
            GitBaseSelection.probableBase(
                among: withDevelop,
                originHEADRef: nil,
                currentBranchName: "feature"
            ) == local("develop")
        )

        let withMaster = [local("feature"), local("master")]
        #expect(
            GitBaseSelection.probableBase(
                among: withMaster,
                originHEADRef: nil,
                currentBranchName: "feature"
            ) == local("master")
        )

        let withMain = [local("topic"), local("main"), local("develop")]
        #expect(
            GitBaseSelection.probableBase(
                among: withMain,
                originHEADRef: nil,
                currentBranchName: "topic"
            ) == local("main")
        )
    }

    @Test func prefersLocalFallbackOverRemoteOfSameName() {
        let branches = [remote("origin", "main"), local("main"), local("topic")]

        let base = GitBaseSelection.probableBase(
            among: branches,
            originHEADRef: nil,
            currentBranchName: "topic"
        )

        #expect(base == local("main"))
    }

    @Test func usesCurrentBranchWhenNoFallbackExists() {
        let branches = [local("feature/foo"), remote("origin", "feature/foo")]

        let base = GitBaseSelection.probableBase(
            among: branches,
            originHEADRef: nil,
            currentBranchName: "feature/foo"
        )

        #expect(base == local("feature/foo"))
    }

    @Test func returnsNilWhenNothingMatches() {
        let branches = [remote("origin", "feature/foo")]

        let base = GitBaseSelection.probableBase(
            among: branches,
            originHEADRef: nil,
            currentBranchName: nil
        )

        #expect(base == nil)
    }

    @Test func ignoresOriginHEADRefThatIsNotInTheList() {
        let branches = [local("main")]

        let base = GitBaseSelection.probableBase(
            among: branches,
            originHEADRef: "refs/remotes/origin/main",
            currentBranchName: "main"
        )

        #expect(base == local("main"))
    }

    @Test func headListLabelNamesDetachedHonestly() {
        #expect(GitHEAD.branch("main").listLabel == "main")
        #expect(GitHEAD.detached.listLabel == "detached HEAD")
    }
}
