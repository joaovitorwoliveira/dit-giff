import Foundation

/// Finds the `claude` binary. Finder-launched apps get a minimal PATH, so a bare
/// name usually fails — known install locations are checked before asking the login shell.
nonisolated protocol ClaudeBinaryLocating: Sendable {
    func locateClaudeExecutable() async throws -> String
}

/// Executability check for candidate paths. Injected so tests never touch the real disk.
nonisolated protocol ClaudeExecutableChecking: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
}

nonisolated struct FileManagerClaudeExecutableChecker: ClaudeExecutableChecking {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func isExecutableFile(atPath path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }
}

actor ClaudeBinaryLocator: ClaudeBinaryLocating {
    private let runner: any CommandRunner
    private let executableChecker: any ClaudeExecutableChecking
    private let homeDirectoryURL: URL
    private let loginShellPath: String
    private var cachedPath: String?

    init(
        runner: any CommandRunner,
        executableChecker: any ClaudeExecutableChecking = FileManagerClaudeExecutableChecker(),
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        loginShellPath: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    ) {
        self.runner = runner
        self.executableChecker = executableChecker
        self.homeDirectoryURL = homeDirectoryURL
        self.loginShellPath = loginShellPath
    }

    func locateClaudeExecutable() async throws -> String {
        if let cachedPath {
            return cachedPath
        }

        let candidates = Self.candidatePaths(homeDirectoryURL: homeDirectoryURL)
        for path in candidates {
            if executableChecker.isExecutableFile(atPath: path) {
                cachedPath = path
                return path
            }
        }

        if let fromShell = try await resolveViaLoginShell() {
            cachedPath = fromShell
            return fromShell
        }

        throw AgentError.claudeNotFound(searchedPaths: candidates)
    }

    static func candidatePaths(homeDirectoryURL: URL) -> [String] {
        [
            homeDirectoryURL.appendingPathComponent(".local/bin/claude").path,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            homeDirectoryURL.appendingPathComponent(".claude/local/claude").path,
        ]
    }

    private func resolveViaLoginShell() async throws -> String? {
        let output: CommandOutput
        do {
            output = try await runner.run(
                CommandRequest(
                    executable: loginShellPath,
                    arguments: Self.loginShellArguments
                )
            )
        } catch {
            return nil
        }

        guard output.didSucceed else { return nil }
        let path = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, executableChecker.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }

    static let loginShellArguments = ["-l", "-c", "command -v claude"]
}
