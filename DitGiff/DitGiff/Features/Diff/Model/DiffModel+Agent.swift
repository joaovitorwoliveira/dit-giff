import Foundation

extension DiffModel {
    // MARK: - Live agent explain (one-deep queue)

    func enqueueAgentExplanation(for file: DiffFile) {
        enqueueAgentExplanation(target: .file(path: file.path))
    }

    func enqueueAgentExplanation(for hunk: DiffHunk) {
        enqueueAgentExplanation(target: .hunk(id: hunk.id))
    }

    /// The chat panel calls this after consuming a scroll request so a repeat click fires.
    func clearChatScrollRequest() {
        chatScrollRequest = nil
    }

    /// Short label for the thinking bubble — git verb, not a shell dump.
    static func readableToolActivity(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Working" }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens.first == "git", tokens.count >= 2 {
            return "Running git \(tokens[1])"
        }
        if let first = tokens.first {
            let short = first.count > 32 ? String(first.prefix(32)) + "…" : first
            return "Running \(short)"
        }
        return "Working"
    }

    func cancelAgentExplain(clearQueue: Bool) {
        explainGeneration += 1
        pendingExplain?.cancel()
        pendingExplain = nil
        inFlightExplainTarget = nil
        if clearQueue {
            queuedExplainTarget = nil
        }
        streamingMessageID = nil
        streamingExplainTarget = nil
        isThinking = false
        thinkingActivityLabel = nil
    }
}
