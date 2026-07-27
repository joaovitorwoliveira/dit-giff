import Foundation

/// What the one-deep explain queue is working on — file header or hunk actions share it.
nonisolated enum AgentExplainTarget: Equatable, Hashable, Sendable {
    case file(path: String)
    case hunk(id: String)
}
