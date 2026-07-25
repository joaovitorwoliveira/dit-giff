import Foundation
import Testing

@testable import DitGiff

nonisolated struct ClaudeBinaryLocatorTests {
    private let home = URL(fileURLWithPath: "/fake/home", isDirectory: true)
    private let shell = "/fake/login-shell"

    private var candidates: [String] {
        ClaudeBinaryLocator.candidatePaths(homeDirectoryURL: home)
    }

    // MARK: - Known paths

    @Test func prefersAnExistingKnownPathOverAMissingOne() async throws {
        let existing = candidates[2] // /opt/homebrew/bin/claude
        let checker = FakeClaudeExecutableChecker(executablePaths: [existing])
        let runner = FakeCommandRunner()

        let path = try await locator(runner: runner, checker: checker).locateClaudeExecutable()

        #expect(path == existing)
        #expect(await runner.receivedRequests.isEmpty)
    }

    @Test func firstExistingKnownPathWinsWhenSeveralExist() async throws {
        let first = candidates[0]
        let second = candidates[1]
        let checker = FakeClaudeExecutableChecker(executablePaths: [first, second])
        let runner = FakeCommandRunner()

        let path = try await locator(runner: runner, checker: checker).locateClaudeExecutable()

        #expect(path == first)
        #expect(await runner.receivedRequests.isEmpty)
    }

    @Test func doesNotConsultLoginShellWhenAKnownPathExists() async throws {
        let existing = candidates[0]
        let checker = FakeClaudeExecutableChecker(executablePaths: [existing])
        let runner = FakeCommandRunner()
        // Stubbed on purpose: if the locator asked the shell, FakeCommandRunner
        // would record it — and we assert it did not.
        await runner.stub(
            shell,
            ClaudeBinaryLocator.loginShellArguments,
            standardOutput: "/should/not/be/used/claude\n"
        )

        let path = try await locator(runner: runner, checker: checker).locateClaudeExecutable()

        #expect(path == existing)
        #expect(await runner.receivedRequests.isEmpty)
    }

    // MARK: - Login-shell fallback

    @Test func usesLoginShellPathWhenNoKnownPathExists() async throws {
        let fromShell = "/from/shell/bin/claude"
        let checker = FakeClaudeExecutableChecker(executablePaths: [fromShell])
        let runner = FakeCommandRunner()
        await runner.stub(
            shell,
            ClaudeBinaryLocator.loginShellArguments,
            standardOutput: "\(fromShell)\n"
        )

        let path = try await locator(runner: runner, checker: checker).locateClaudeExecutable()

        #expect(path == fromShell)
        let received = await runner.receivedRequests
        #expect(received.count == 1)
        #expect(received[0].executable == shell)
        #expect(received[0].arguments == ClaudeBinaryLocator.loginShellArguments)
    }

    @Test func emptyShellOutputBecomesClaudeNotFound() async throws {
        let checker = FakeClaudeExecutableChecker(executablePaths: [])
        let runner = FakeCommandRunner()
        await runner.stub(
            shell,
            ClaudeBinaryLocator.loginShellArguments,
            standardOutput: ""
        )

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await locator(runner: runner, checker: checker).locateClaudeExecutable()
        }
        #expect(thrown == .claudeNotFound(searchedPaths: candidates))
    }

    @Test func whitespaceOnlyShellOutputBecomesClaudeNotFound() async throws {
        let checker = FakeClaudeExecutableChecker(executablePaths: [])
        let runner = FakeCommandRunner()
        await runner.stub(
            shell,
            ClaudeBinaryLocator.loginShellArguments,
            standardOutput: "   \n\t  "
        )

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await locator(runner: runner, checker: checker).locateClaudeExecutable()
        }
        #expect(thrown == .claudeNotFound(searchedPaths: candidates))
    }

    @Test func nonexistentShellPathBecomesClaudeNotFound() async throws {
        let missing = "/shell/said/this/claude"
        let checker = FakeClaudeExecutableChecker(executablePaths: [])
        let runner = FakeCommandRunner()
        await runner.stub(
            shell,
            ClaudeBinaryLocator.loginShellArguments,
            standardOutput: "\(missing)\n"
        )

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await locator(runner: runner, checker: checker).locateClaudeExecutable()
        }
        #expect(thrown == .claudeNotFound(searchedPaths: candidates))
        #expect(checker.checkCount >= candidates.count + 1)
    }

    @Test func claudeNotFoundCarriesTheTriedKnownPaths() async throws {
        let checker = FakeClaudeExecutableChecker(executablePaths: [])
        let runner = FakeCommandRunner()
        await runner.stub(
            shell,
            ClaudeBinaryLocator.loginShellArguments,
            standardOutput: ""
        )

        let thrown = await #expect(throws: AgentError.self) {
            _ = try await locator(runner: runner, checker: checker).locateClaudeExecutable()
        }
        guard case let .claudeNotFound(searchedPaths)? = thrown else {
            Issue.record("expected claudeNotFound, got \(String(describing: thrown))")
            return
        }
        #expect(searchedPaths == candidates)
        #expect(searchedPaths.count == 4)
        #expect(AgentError.claudeNotFound(searchedPaths: searchedPaths).errorDescription?
            .contains(candidates[0]) == true)
    }

    // MARK: - Cache

    @Test func secondLocateDoesNotRepeatWork() async throws {
        let existing = candidates[1]
        let checker = FakeClaudeExecutableChecker(executablePaths: [existing])
        let runner = FakeCommandRunner()
        let subject = locator(runner: runner, checker: checker)

        let first = try await subject.locateClaudeExecutable()
        let checksAfterFirst = checker.checkCount
        let second = try await subject.locateClaudeExecutable()

        #expect(first == existing)
        #expect(second == existing)
        #expect(checker.checkCount == checksAfterFirst)
        #expect(await runner.receivedRequests.isEmpty)
    }

    @Test func cachedShellHitDoesNotReconsultShell() async throws {
        let fromShell = "/from/shell/bin/claude"
        let checker = FakeClaudeExecutableChecker(executablePaths: [fromShell])
        let runner = FakeCommandRunner()
        await runner.stub(
            shell,
            ClaudeBinaryLocator.loginShellArguments,
            standardOutput: "\(fromShell)\n"
        )
        let subject = locator(runner: runner, checker: checker)

        _ = try await subject.locateClaudeExecutable()
        _ = try await subject.locateClaudeExecutable()

        #expect(await runner.receivedRequests.count == 1)
    }

    // MARK: - Harness

    private func locator(
        runner: FakeCommandRunner,
        checker: FakeClaudeExecutableChecker
    ) -> ClaudeBinaryLocator {
        ClaudeBinaryLocator(
            runner: runner,
            executableChecker: checker,
            homeDirectoryURL: home,
            loginShellPath: shell
        )
    }
}

/// In-memory executability table. Counts checks so cache tests can prove no FS work.
private final class FakeClaudeExecutableChecker: ClaudeExecutableChecking, @unchecked Sendable {
    private let executablePaths: Set<String>
    private let lock = NSLock()
    private var _checkCount = 0

    var checkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _checkCount
    }

    init(executablePaths: [String]) {
        self.executablePaths = Set(executablePaths)
    }

    func isExecutableFile(atPath path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _checkCount += 1
        return executablePaths.contains(path)
    }
}
