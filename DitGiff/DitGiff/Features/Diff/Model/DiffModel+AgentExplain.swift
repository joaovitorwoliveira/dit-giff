import Foundation

extension DiffModel {
    // MARK: - Explain orchestration

    func enqueueAgentExplanation(target: AgentExplainTarget) {
        guard agent != nil, patch(for: target) != nil else { return }

        if let cached = completedExplanations[target] {
            presentCachedExplanation(target: target, text: cached)
            return
        }

        if inFlightExplainTarget == target {
            openThreadIfNeeded()
            if let messageID = streamingMessageID ?? explanationMessageIDs[target] {
                requestChatScroll(to: messageID)
            }
            return
        }

        if inFlightExplainTarget == nil {
            startAgentExplanation(target: target)
            return
        }

        // Running slot is busy — replace whoever was waiting. Never grow past one.
        queuedExplainTarget = target
        openThreadIfNeeded()
    }

    private func presentCachedExplanation(target: AgentExplainTarget, text: String) {
        openThreadIfNeeded()
        if let messageID = explanationMessageIDs[target] {
            requestChatScroll(to: messageID)
            return
        }
        // Cache survived without a thread entry (should not happen in normal flow).
        let created = message(
            role: .agent,
            text: text,
            location: explainLocation(for: target),
            hunkID: explainHunkID(for: target)
        )
        explanationMessageIDs[target] = created.id
        append(created)
        requestChatScroll(to: created.id)
    }

    private func requestChatScroll(to messageID: Int) {
        chatScrollNonce &+= 1
        chatScrollRequest = DiffChatScrollRequest(messageID: messageID, nonce: chatScrollNonce)
    }

    private func startAgentExplanation(target: AgentExplainTarget) {
        guard
            let agent,
            let patch = patch(for: target),
            let repositoryRoot
        else {
            return
        }

        let filePath = explainFilePath(for: target)

        inFlightExplainTarget = target
        queuedExplainTarget = nil
        streamingMessageID = nil
        streamingExplainTarget = target

        openThreadIfNeeded()
        thread?.hunkID = explainHunkID(for: target)
        thread?.location = explainLocation(for: target)
        // One entry per target — drop a prior incomplete/error bubble before streaming again.
        removeExplanationMessage(for: target)
        isThinking = true
        thinkingActivityLabel = nil

        let scope: AgentExplainScope
        switch target {
        case .file:
            scope = .file
        case let .hunk(id):
            let location = hunk(withID: id)?.location ?? fileName(forPath: filePath)
            scope = .hunk(id: id, location: location)
        }

        let request = AgentExplainRequest(
            repositoryRoot: repositoryRoot,
            filePath: filePath,
            patch: patch,
            baseName: baseBranch,
            compareName: compareBranch,
            model: chatModel.agentModel,
            effort: reasoningEffort.agentEffort,
            scope: scope
        )

        let generation = explainGeneration
        pendingExplain?.cancel()
        pendingExplain = Task { [weak self] in
            await self?.consumeAgentExplanation(
                agent: agent,
                request: request,
                target: target,
                generation: generation
            )
        }
    }

    private func patch(for target: AgentExplainTarget) -> String? {
        switch target {
        case let .file(path):
            filePatchBodies[path]
        case let .hunk(id):
            hunkPatchBodies[id]
        }
    }

    private func explainFilePath(for target: AgentExplainTarget) -> String {
        switch target {
        case let .file(path):
            path
        case let .hunk(id):
            hunk(withID: id)?.filePath ?? id
        }
    }

    private func explainLocation(for target: AgentExplainTarget) -> String? {
        switch target {
        case let .file(path):
            fileName(forPath: path)
        case let .hunk(id):
            hunk(withID: id)?.location
        }
    }

    private func explainHunkID(for target: AgentExplainTarget) -> String? {
        guard case let .hunk(id) = target else { return nil }
        return id
    }

    private func removeExplanationMessage(for target: AgentExplainTarget) {
        guard let messageID = explanationMessageIDs.removeValue(forKey: target) else { return }
        thread?.messages.removeAll { $0.id == messageID }
    }

    private func consumeAgentExplanation(
        agent: any DiffAgent,
        request: AgentExplainRequest,
        target: AgentExplainTarget,
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
            completedExplanations[target] = accumulated
            isThinking = false
            thinkingActivityLabel = nil
            if streamingMessageID == nil, !accumulated.isEmpty {
                appendStreamingDelta(accumulated)
            }
            if let streamingMessageID {
                explanationMessageIDs[target] = streamingMessageID
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

    private func appendStreamingDelta(_ text: String) {
        isThinking = false
        thinkingActivityLabel = nil
        let target = streamingExplainTarget
        let location = target.flatMap { explainLocation(for: $0) }
        let messageHunkID = target.flatMap { explainHunkID(for: $0) }
        if let streamingMessageID,
           let index = thread?.messages.firstIndex(where: { $0.id == streamingMessageID })
        {
            var messages = thread?.messages ?? []
            messages[index] = DiffChatMessage(
                id: streamingMessageID,
                role: .agent,
                text: text,
                location: location,
                hunkID: messageHunkID
            )
            thread?.messages = messages
            return
        }

        let created = message(
            role: .agent,
            text: text,
            location: location,
            hunkID: messageHunkID
        )
        streamingMessageID = created.id
        if let target {
            explanationMessageIDs[target] = created.id
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
        let target = streamingExplainTarget
        let location = target.flatMap { explainLocation(for: $0) }
        let messageHunkID = target.flatMap { explainHunkID(for: $0) }
        openThreadIfNeeded()
        // Replace only this target's bubble — earlier explanations in the thread stay.
        if let messageID = streamingMessageID,
           let index = thread?.messages.firstIndex(where: { $0.id == messageID })
        {
            var messages = thread?.messages ?? []
            messages[index] = DiffChatMessage(
                id: messageID,
                role: .agent,
                text: text,
                location: location,
                hunkID: messageHunkID
            )
            thread?.messages = messages
            if let target {
                explanationMessageIDs[target] = messageID
            }
            streamingMessageID = nil
            return
        }

        if let target {
            removeExplanationMessage(for: target)
            let created = message(
                role: .agent,
                text: text,
                location: location,
                hunkID: messageHunkID
            )
            explanationMessageIDs[target] = created.id
            append(created)
        } else {
            append(message(role: .agent, text: text, location: location, hunkID: messageHunkID))
        }
        streamingMessageID = nil
    }

    private func finishAgentExplainSlot(cancelled: Bool, generation: Int) {
        guard generation == explainGeneration else { return }
        let next = cancelled ? nil : queuedExplainTarget
        inFlightExplainTarget = nil
        queuedExplainTarget = nil
        streamingMessageID = nil
        streamingExplainTarget = nil
        pendingExplain = nil
        if cancelled {
            isThinking = false
            thinkingActivityLabel = nil
            return
        }
        if let next {
            startAgentExplanation(target: next)
        }
    }
}
