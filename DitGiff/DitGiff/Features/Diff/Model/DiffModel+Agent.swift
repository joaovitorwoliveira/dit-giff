import Foundation

extension DiffModel {
    // MARK: - Live agent explain (one-deep queue)

    func enqueueAgentExplanation(for file: DiffFile) {
        guard agent != nil, filePatchBodies[file.path] != nil else { return }

        if let cached = completedFileExplanations[file.path] {
            presentCachedExplanation(path: file.path, text: cached)
            return
        }

        if inFlightExplainPath == file.path {
            openThreadIfNeeded()
            if let messageID = streamingMessageID ?? explanationMessageIDs[file.path] {
                requestChatScroll(to: messageID)
            }
            return
        }

        if inFlightExplainPath == nil {
            startAgentExplanation(path: file.path)
            return
        }

        // Running slot is busy — replace whoever was waiting. Never grow past one.
        queuedExplainPath = file.path
        openThreadIfNeeded()
    }

    private func presentCachedExplanation(path: String, text: String) {
        openThreadIfNeeded()
        if let messageID = explanationMessageIDs[path] {
            requestChatScroll(to: messageID)
            return
        }
        // Cache survived without a thread entry (should not happen in normal flow).
        let created = message(
            role: .agent,
            text: text,
            location: fileName(forPath: path)
        )
        explanationMessageIDs[path] = created.id
        append(created)
        requestChatScroll(to: created.id)
    }

    private func requestChatScroll(to messageID: Int) {
        chatScrollNonce &+= 1
        chatScrollRequest = DiffChatScrollRequest(messageID: messageID, nonce: chatScrollNonce)
    }

    /// The chat panel calls this after consuming a scroll request so a repeat click fires.
    func clearChatScrollRequest() {
        chatScrollRequest = nil
    }

    private func startAgentExplanation(path: String) {
        guard
            let agent,
            let patch = filePatchBodies[path],
            let repositoryRoot
        else {
            return
        }

        inFlightExplainPath = path
        queuedExplainPath = nil
        streamingMessageID = nil
        streamingFilePath = path

        openThreadIfNeeded()
        thread?.hunkID = nil
        thread?.location = fileName(forPath: path)
        // One entry per file — drop a prior incomplete/error bubble before streaming again.
        removeExplanationMessage(forPath: path)
        isThinking = true
        thinkingActivityLabel = nil

        let request = AgentExplainRequest(
            repositoryRoot: repositoryRoot,
            filePath: path,
            patch: patch,
            baseName: baseBranch,
            compareName: compareBranch,
            model: chatModel.agentModel,
            effort: reasoningEffort.agentEffort
        )

        let generation = explainGeneration
        pendingExplain?.cancel()
        pendingExplain = Task { [weak self] in
            await self?.consumeAgentExplanation(
                agent: agent,
                request: request,
                generation: generation
            )
        }
    }

    private func removeExplanationMessage(forPath path: String) {
        guard let messageID = explanationMessageIDs.removeValue(forKey: path) else { return }
        thread?.messages.removeAll { $0.id == messageID }
    }

    private func consumeAgentExplanation(
        agent: any DiffAgent,
        request: AgentExplainRequest,
        generation: Int
    ) async {
        var accumulated = ""
        var sawFinished = false

        do {
            for try await event in agent.explainFile(request) {
                guard !Task.isCancelled, generation == explainGeneration else {
                    finishAgentExplainSlot(cancelled: true, generation: generation)
                    return
                }
                switch event {
                case let .textDelta(delta):
                    accumulated += delta
                    appendStreamingDelta(accumulated)
                case let .toolStarted(command):
                    // Text may already be on screen; tools run silent for minutes without
                    // this — the panel must never look idle while the stream is alive.
                    thinkingActivityLabel = Self.readableToolActivity(command)
                    isThinking = true
                case .finished:
                    sawFinished = true
                }
            }
        } catch is CancellationError {
            finishAgentExplainSlot(cancelled: true, generation: generation)
            return
        } catch {
            guard !Task.isCancelled, generation == explainGeneration else {
                finishAgentExplainSlot(cancelled: true, generation: generation)
                return
            }
            presentAgentError(error)
            finishAgentExplainSlot(cancelled: false, generation: generation)
            return
        }

        guard !Task.isCancelled, generation == explainGeneration else {
            finishAgentExplainSlot(cancelled: true, generation: generation)
            return
        }

        // `.finished` is the only proof of a complete reply. Ending without it must
        // not be cached — and must not leave unmarked partial prose in the thread,
        // because a cut-off caveat reads as the opposite claim.
        if sawFinished {
            completedFileExplanations[request.filePath] = accumulated
            isThinking = false
            thinkingActivityLabel = nil
            if streamingMessageID == nil, !accumulated.isEmpty {
                appendStreamingDelta(accumulated)
            }
            if let streamingMessageID {
                explanationMessageIDs[request.filePath] = streamingMessageID
            }
        } else {
            presentAgentError(
                AgentError.failed(
                    reason: "The reply ended before it finished. This explanation is incomplete — ask again."
                )
            )
        }

        finishAgentExplainSlot(cancelled: false, generation: generation)
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

    private func appendStreamingDelta(_ text: String) {
        isThinking = false
        thinkingActivityLabel = nil
        let location = streamingFilePath.map(fileName(forPath:))
        if let streamingMessageID,
           let index = thread?.messages.firstIndex(where: { $0.id == streamingMessageID })
        {
            var messages = thread?.messages ?? []
            messages[index] = DiffChatMessage(
                id: streamingMessageID,
                role: .agent,
                text: text,
                location: location,
                hunkID: nil
            )
            thread?.messages = messages
            return
        }

        let created = message(role: .agent, text: text, location: location)
        streamingMessageID = created.id
        if let streamingFilePath {
            explanationMessageIDs[streamingFilePath] = created.id
        }
        append(created)
    }

    private func presentAgentError(_ error: Error) {
        isThinking = false
        thinkingActivityLabel = nil
        let text: String
        if let agentError = error as? AgentError {
            text = agentError.errorDescription ?? String(describing: agentError)
        } else {
            text = error.localizedDescription
        }
        let location = streamingFilePath.map(fileName(forPath:))
        openThreadIfNeeded()
        // Replace only this file's bubble — earlier explanations in the thread stay.
        if let messageID = streamingMessageID,
           let index = thread?.messages.firstIndex(where: { $0.id == messageID })
        {
            var messages = thread?.messages ?? []
            messages[index] = DiffChatMessage(
                id: messageID,
                role: .agent,
                text: text,
                location: location,
                hunkID: nil
            )
            thread?.messages = messages
            if let streamingFilePath {
                explanationMessageIDs[streamingFilePath] = messageID
            }
            streamingMessageID = nil
            return
        }

        if let streamingFilePath {
            removeExplanationMessage(forPath: streamingFilePath)
            let created = message(role: .agent, text: text, location: location)
            explanationMessageIDs[streamingFilePath] = created.id
            append(created)
        } else {
            append(message(role: .agent, text: text, location: location))
        }
        streamingMessageID = nil
    }

    private func finishAgentExplainSlot(cancelled: Bool, generation: Int) {
        guard generation == explainGeneration else { return }
        let next = cancelled ? nil : queuedExplainPath
        inFlightExplainPath = nil
        queuedExplainPath = nil
        streamingMessageID = nil
        streamingFilePath = nil
        pendingExplain = nil
        if cancelled {
            isThinking = false
            thinkingActivityLabel = nil
            return
        }
        if let next {
            startAgentExplanation(path: next)
        }
    }

    func cancelAgentExplain(clearQueue: Bool) {
        explainGeneration += 1
        pendingExplain?.cancel()
        pendingExplain = nil
        inFlightExplainPath = nil
        if clearQueue {
            queuedExplainPath = nil
        }
        streamingMessageID = nil
        streamingFilePath = nil
        isThinking = false
        thinkingActivityLabel = nil
    }

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
