import Foundation

nonisolated struct CommandRequest: Equatable, Sendable {
    /// A bare name resolved through `PATH` ("git") or an absolute path ("/bin/echo").
    let executable: String
    let arguments: [String]
    let workingDirectory: URL?
    /// Merged over the inherited environment, so `PATH` survives unless replaced.
    let environment: [String: String]
    /// Written to the child's stdin and closed. Nil leaves stdin alone (inherited).
    let standardInput: String?

    init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:],
        standardInput: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.standardInput = standardInput
    }

    var invocation: CommandInvocation {
        CommandInvocation(executable: executable, arguments: arguments)
    }

    var displayString: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

/// A command's identity ignoring where it ran — what a test stubs on.
nonisolated struct CommandInvocation: Hashable, Sendable {
    let executable: String
    let arguments: [String]

    init(executable: String, arguments: [String] = []) {
        self.executable = executable
        self.arguments = arguments
    }
}

nonisolated struct CommandOutput: Equatable, Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    init(standardOutput: String = "", standardError: String = "", exitCode: Int32 = 0) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }

    var didSucceed: Bool { exitCode == 0 }

    /// Only for callers where a non-zero exit genuinely means something went wrong.
    func requireSuccess(for request: CommandRequest) throws -> String {
        guard didSucceed else {
            throw CommandFailure.exitedWithFailure(request: request, output: self)
        }
        return standardOutput
    }
}

nonisolated enum CommandStreamEvent: Equatable, Sendable {
    case standardOutputLine(String)
    case standardErrorLine(String)
    case exited(code: Int32)
}

/// The seam. Everything that wants to run `git` or `claude` goes through here, and
/// exactly one type behind it touches `Process`.
nonisolated protocol CommandRunner: Sendable {
    func run(_ request: CommandRequest) async throws -> CommandOutput
    /// Cancelling the consuming Task ends the stream without throwing and kills the
    /// child. Stream end is therefore not proof the output is complete — the consumer
    /// needs its own completeness criterion.
    func stream(_ request: CommandRequest) -> AsyncThrowingStream<CommandStreamEvent, Error>
}

/// A non-zero exit code is deliberately not in here: it is an answer, not a failure.
/// `git diff --quiet` exits 1 to say "there are changes". Those travel in
/// `CommandOutput` and only become errors when a caller asks for `requireSuccess`.
nonisolated enum CommandFailure: Error, Equatable, LocalizedError {
    case launchFailed(executable: String, reason: String)
    case exitedWithFailure(request: CommandRequest, output: CommandOutput)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(executable, reason):
            "Could not run \(executable): \(reason)"
        case let .exitedWithFailure(request, output):
            """
            `\(request.displayString)` exited with code \(output.exitCode).
            \(output.standardError.isEmpty ? "No output on stderr." : output.standardError)
            """
        }
    }
}
