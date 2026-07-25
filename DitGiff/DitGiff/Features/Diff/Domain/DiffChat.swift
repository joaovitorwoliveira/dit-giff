nonisolated enum DiffChatRole: Equatable, Sendable {
    case user
    case agent
}

nonisolated struct DiffChatMessage: Identifiable, Equatable, Sendable {
    let id: Int
    let role: DiffChatRole
    let text: String
    /// The chip above the bubble: a hunk location, a selection, or nothing.
    let location: String?
    /// Set when the message points at a hunk the reader can jump to.
    let hunkID: String?

    init(id: Int, role: DiffChatRole, text: String, location: String? = nil, hunkID: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.location = location
        self.hunkID = hunkID
    }
}

nonisolated struct DiffChatThread: Equatable, Sendable {
    /// The hunk the thread started from, which is what earns the canned follow-up reply.
    var hunkID: String?
    var location: String?
    var messages: [DiffChatMessage]

    init(hunkID: String? = nil, location: String? = nil, messages: [DiffChatMessage] = []) {
        self.hunkID = hunkID
        self.location = location
        self.messages = messages
    }
}

nonisolated enum DiffChatModelOption: CaseIterable, Identifiable, Sendable {
    case fable
    case opus5
    case sonnet
    case haiku

    var id: Self { self }

    var title: String {
        switch self {
        case .fable: "Fable"
        case .opus5: "Opus 5"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        }
    }
}

nonisolated enum DiffReasoningEffort: CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case max

    var id: Self { self }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }
}

/// The spinner next to "Thinking…". It carries the copy it cycles, so the rule stays
/// here while the words stay with whoever owns them. Pure arithmetic over a step the
/// view ticks, so the model never owns a timer.
nonisolated struct DiffThinkingIndicator: Equatable, Sendable {
    /// The word changes every sixth glyph, slow enough to read.
    static let stepsPerWord = 6

    let glyphs: [String]
    let words: [String]

    func glyph(step: Int) -> String {
        cycle(glyphs, at: step)
    }

    func word(step: Int) -> String {
        cycle(words, at: step / Self.stepsPerWord)
    }

    private func cycle(_ values: [String], at step: Int) -> String {
        guard !values.isEmpty else {
            preconditionFailure("The thinking indicator needs at least one value to cycle.")
        }
        let index = ((step % values.count) + values.count) % values.count
        return values[index]
    }
}
