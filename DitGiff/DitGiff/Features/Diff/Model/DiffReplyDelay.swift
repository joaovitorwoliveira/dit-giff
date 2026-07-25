import Foundation


/// The pause before a canned answer arrives. It is a seam so tests do not wait on the
/// clock, and so the delay stays out of the rules it decorates.
nonisolated protocol DiffReplyDelay: Sendable {
    func wait() async throws
}

/// What the prototype does: a wait long enough to read the question back.
nonisolated struct RandomDiffReplyDelay: DiffReplyDelay {
    let milliseconds: ClosedRange<Int>

    init(milliseconds: ClosedRange<Int>) {
        self.milliseconds = milliseconds
    }

    func wait() async throws {
        try await Task.sleep(for: .milliseconds(Int.random(in: milliseconds)))
    }
}

/// Live sessions have no fake round-trip. Slice 4 will own real latency.
nonisolated struct NullDiffReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}

/// The only door from `DiffModel` into `DiffSampleData`'s canned agent copy.
/// Present in sample/preview mode; **absent** in a live session. Every path that would
/// invent an agent answer must go through this value — so a live model cannot reach
/// that copy without growing a second source, which is the point of Slice 4.
struct DiffCannedAgent: Sendable {
    let openingMessage: String
    let thinkingIndicator: DiffThinkingIndicator
    let fallbackReply: String
    let defaultChatModel: DiffChatModelOption
    let defaultReasoningEffort: DiffReasoningEffort

    func explainSelectionReply(lineCountLabel: String) -> String {
        DiffSampleData.explainSelectionReply(lineCountLabel: lineCountLabel)
    }

    func selectionQuestionReply(location: String, question: String) -> String {
        DiffSampleData.selectionQuestionReply(location: location, question: question)
    }

    static var prototype: DiffCannedAgent {
        DiffCannedAgent(
            openingMessage: DiffSampleData.openingAgentMessage,
            thinkingIndicator: DiffSampleData.thinkingIndicator,
            fallbackReply: DiffSampleData.fallbackReply,
            defaultChatModel: DiffSampleData.defaultChatModel,
            defaultReasoningEffort: DiffSampleData.defaultReasoningEffort
        )
    }
}
