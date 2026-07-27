import Foundation

extension DiffModel {
    // MARK: - Chat

    func closeChat() {
        isChatOpen = false
    }

    /// The panel with no hunk behind it: the agent introduces itself.
    /// No-ops when there is no agent — absence is absence.
    func openChat() {
        guard let agent = cannedAgent else { return }
        if thread == nil {
            thread = DiffChatThread(
                messages: [message(role: .agent, text: agent.openingMessage)]
            )
        }
        isChatOpen = true
    }

    /// Whether the file header's Explain control can produce an answer.
    /// Sample: canned hunk copy. Live: a real agent plus a text patch body for that path.
    func canExplainFile(_ file: DiffFile) -> Bool {
        if cannedAgent != nil {
            guard let hunk = file.hunks.first else { return canUseSampleAgent }
            return hunk.explanation != nil
        }
        return agent != nil && filePatchBodies[file.path] != nil
    }

    /// Whether the hunk's Explain / chat actions can ask the agent now.
    func canExplain(_ hunk: DiffHunk) -> Bool {
        if cannedAgent != nil {
            return hunk.explanation != nil
        }
        return agent != nil && hunkPatchBodies[hunk.id] != nil
    }

    /// Whether explaining the current selection can produce an agent answer.
    var canExplainSelection: Bool { cannedAgent != nil && selection != nil }

    /// Whether asking about the current selection can produce an agent answer.
    var canAskAboutSelection: Bool { cannedAgent != nil && selection != nil }

    /// The file header's chat button. Sample keeps the prototype path. Live asks the
    /// injected agent, with a one-deep queue and a completed cache per file.
    func explainFile(_ file: DiffFile) {
        if cannedAgent != nil {
            guard let hunk = file.hunks.first else {
                openChat()
                return
            }
            explain(hunk)
            return
        }
        enqueueAgentExplanation(for: file)
    }

    func explain(_ hunk: DiffHunk) {
        if cannedAgent != nil {
            guard let explanation = hunk.explanation else { return }
            startThread(from: hunk, answering: explanation)
            return
        }
        enqueueAgentExplanation(for: hunk)
    }

    /// The marker on a hunk that carries an analysis note.
    func openNote(_ hunk: DiffHunk) {
        guard let note = hunk.note else { return }
        startThread(from: hunk, answering: note)
    }

    func explainSelection() {
        guard let agent = cannedAgent, let selection else { return }
        let reply = agent.explainSelectionReply(lineCountLabel: selection.lineCountLabel)
        self.selection = nil
        openThreadIfNeeded()
        think(reply: reply, location: selection.location, hunkID: nil)
    }

    /// The question typed into the selection popover. An empty one means the reader
    /// pressed send with nothing to add.
    func askAboutSelection(_ question: String) {
        guard let agent = cannedAgent, let selection else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            explainSelection()
            return
        }
        let location = selection.location
        self.selection = nil
        openThreadIfNeeded()
        append(message(role: .user, text: trimmed, location: location))
        think(
            reply: agent.selectionQuestionReply(location: location, question: trimmed),
            location: nil,
            hunkID: nil
        )
    }

    /// The composer at the bottom of the panel. No-ops without an agent.
    func send(_ text: String) {
        guard let agent = cannedAgent else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if thread == nil {
            thread = DiffChatThread(location: "\(compareBranch) → \(baseBranch)")
        }
        isChatOpen = true
        append(message(role: .user, text: trimmed))
        guard let reply = nextReply(fallback: agent.fallbackReply) else { return }
        think(reply: reply, location: nil, hunkID: nil)
    }

    /// The hunk the thread started from answers once; after that the agent has nothing
    /// canned left to say. `nil` when the hunk's reply is absent — do not invent one.
    private func nextReply(fallback: String) -> String? {
        guard
            let hunkID = thread?.hunkID,
            !usedHunkReplies.contains(hunkID),
            let hunk = hunk(withID: hunkID)
        else {
            return fallback
        }
        usedHunkReplies.insert(hunkID)
        return hunk.reply
    }
}
