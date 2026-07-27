import Foundation

/// Product-level AI seam. Features map UI choices onto these types; adapters
/// behind this protocol are the only place that knows a concrete CLI.
nonisolated protocol DiffAgent: Sendable {
    func explainFile(_ request: AgentExplainRequest) -> AsyncThrowingStream<AgentEvent, Error>
}

nonisolated enum AgentEvent: Equatable, Sendable {
    case textDelta(String)
    case toolStarted(command: String)
    case finished
}

nonisolated enum AgentError: Error, Equatable, LocalizedError {
    case claudeNotFound(searchedPaths: [String])
    case notLoggedIn
    case noNetwork
    case timedOut(afterSeconds: Int)
    case failed(reason: String)

    var errorDescription: String? {
        switch self {
        case let .claudeNotFound(searchedPaths):
            let paths = searchedPaths.joined(separator: ", ")
            return "Claude Code was not found. Looked in: \(paths)."
        case .notLoggedIn:
            return "Claude Code is not logged in. Run `claude auth login` in a terminal, then try again."
        case .noNetwork:
            return "Could not reach the Claude API. Check the network connection and try again."
        case let .timedOut(afterSeconds):
            return "Claude Code produced no output for \(afterSeconds) seconds."
        case let .failed(reason):
            return reason
        }
    }
}

/// CLI model aliases accepted by `claude --model`. Distinct from the UI enums in Features.
nonisolated enum AgentModel: String, Equatable, Sendable, CaseIterable {
    case fable
    case opus
    case sonnet
    case haiku

    var cliValue: String { rawValue }
}

/// CLI effort aliases accepted by `claude --effort`. Distinct from the UI enums in Features.
nonisolated enum AgentEffort: String, Equatable, Sendable, CaseIterable {
    case low
    case medium
    case high
    case xhigh
    case max

    var cliValue: String { rawValue }
}

nonisolated enum AgentExplainScope: Equatable, Sendable {
    case file
    case hunk(id: String, location: String)
}

nonisolated struct AgentExplainRequest: Equatable, Sendable {
    let repositoryRoot: URL
    /// Path relative to the repository root, as shown in the diff.
    let filePath: String
    /// Patch slice for this request — whole file or one hunk, never both.
    let patch: String
    let baseName: String
    let compareName: String
    let model: AgentModel
    let effort: AgentEffort
    let scope: AgentExplainScope

    init(
        repositoryRoot: URL,
        filePath: String,
        patch: String,
        baseName: String,
        compareName: String,
        model: AgentModel,
        effort: AgentEffort,
        scope: AgentExplainScope = .file
    ) {
        self.repositoryRoot = repositoryRoot
        self.filePath = filePath
        self.patch = patch
        self.baseName = baseName
        self.compareName = compareName
        self.model = model
        self.effort = effort
        self.scope = scope
    }
}
