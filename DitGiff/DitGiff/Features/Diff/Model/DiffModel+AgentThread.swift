import Foundation

extension DiffModel {
    // MARK: - Agent thread primitives

    func startThread(from hunk: DiffHunk, answering text: String) {
        openThreadIfNeeded()
        thread?.hunkID = hunk.id
        think(reply: text, location: hunk.location, hunkID: hunk.id)
    }

    func openThreadIfNeeded() {
        if thread == nil {
            thread = DiffChatThread()
        }
        isChatOpen = true
    }

    func think(reply: String, location: String?, hunkID: String?) {
        pendingReply?.cancel()
        isThinking = true
        pendingReply = Task { [weak self] in
            do {
                try await self?.replyDelay.wait()
            } catch {
                // The only way out of the wait is cancellation, and a cancelled round
                // trip has no answer to deliver.
                return
            }
            guard !Task.isCancelled, let self else { return }
            isThinking = false
            append(message(role: .agent, text: reply, location: location, hunkID: hunkID))
        }
    }

    func append(_ message: DiffChatMessage) {
        guard thread != nil else {
            preconditionFailure("A message was appended before a thread existed.")
        }
        thread?.messages.append(message)
    }

    func message(
        role: DiffChatRole,
        text: String,
        location: String? = nil,
        hunkID: String? = nil
    ) -> DiffChatMessage {
        defer { nextMessageID += 1 }
        return DiffChatMessage(
            id: nextMessageID,
            role: role,
            text: text,
            location: location,
            hunkID: hunkID
        )
    }
}
