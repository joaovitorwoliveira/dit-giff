/// Features → Core/Agent. Keeps UI picker enums out of the agent seam so a CLI
/// swap does not drag DiffChatPanel types with it.

extension DiffChatModelOption {
    var agentModel: AgentModel {
        switch self {
        case .fable: .fable
        case .opus5: .opus
        case .sonnet: .sonnet
        case .haiku: .haiku
        }
    }
}

extension DiffReasoningEffort {
    var agentEffort: AgentEffort {
        switch self {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .max: .max
        }
    }
}
