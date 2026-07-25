/// The vocabulary of a diff as the review screen needs it. Everything here is a value:
/// what changed, how it is grouped, and how a piece of it is named out loud.
nonisolated enum DiffFileStatus: Equatable, Sendable {
    case added
    case deleted
    case modified
    case renamed

    var title: String {
        switch self {
        case .added: "Added"
        case .deleted: "Deleted"
        case .modified: "Modified"
        case .renamed: "Renamed"
        }
    }
}

nonisolated enum DiffLineKind: Equatable, Sendable {
    case context
    case addition
    case deletion

    /// The character in the sign column. Context lines carry no sign.
    var sign: String {
        switch self {
        case .context: ""
        case .addition: "+"
        case .deletion: "-"
        }
    }
}

/// A run of a line's text. The intra-line word change is a segment with
/// `isHighlighted` on, so rendering never has to look for it inside a string.
nonisolated struct DiffLineSegment: Equatable, Sendable {
    let text: String
    let isHighlighted: Bool

    init(text: String, isHighlighted: Bool = false) {
        self.text = text
        self.isHighlighted = isHighlighted
    }
}

nonisolated struct DiffLine: Equatable, Sendable {
    /// Absent on an addition: the line did not exist before the change.
    let oldNumber: Int?
    /// Absent on a deletion: the line does not exist after the change.
    let newNumber: Int?
    let kind: DiffLineKind
    let segments: [DiffLineSegment]

    var text: String {
        segments.map(\.text).joined()
    }

    /// The number a selection reports and the gutter reads out: the line as it stands
    /// after the change, falling back to where it used to be for deletions.
    var displayedNumber: Int? {
        newNumber ?? oldNumber
    }
}

/// One `@@` block of a file: its own read state, its own note, its own explanation.
nonisolated struct DiffHunk: Identifiable, Equatable, Sendable {
    let id: String
    let filePath: String
    let header: String
    /// The chip a message carries back, e.g. "BillingGuard.swift:142".
    let location: String
    /// What an attentive reviewer would notice here. Absent when there is nothing to say.
    let note: String?
    /// Agent explanation for this hunk. `nil` until Slice 4 — absence is not an empty string.
    let explanation: String?
    /// The canned answer to the first follow-up question in this hunk's thread.
    /// `nil` when there is no agent reply yet.
    let reply: String?
    let lines: [DiffLine]
}

/// Whether the diff screen has something real to draw, is still fetching it, or failed.
nonisolated enum DiffLoadState: Equatable, Sendable {
    case loading
    case loaded
    case failed(message: String)
}

nonisolated struct DiffFile: Identifiable, Equatable, Sendable {
    let path: String
    let status: DiffFileStatus
    let additions: Int
    let deletions: Int
    let hunks: [DiffHunk]

    var id: String { path }

    /// "Sources/Billing/" — with the trailing separator, empty for a file at the root.
    var directory: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[path.startIndex...slash])
    }

    var name: String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Empty rather than "+0": a file with no additions shows nothing.
    var additionsLabel: String {
        additions == 0 ? "" : "+\(additions)"
    }

    var deletionsLabel: String {
        deletions == 0 ? "" : "\(DiffFormat.minusSign)\(deletions)"
    }
}

/// The sidebar tree. Directories carry their depth so a row knows its own indentation
/// without walking back up.
nonisolated struct DiffTreeDirectory: Identifiable, Equatable, Sendable {
    /// "Sources/Billing/" — unique, and what the open/closed state is keyed on.
    let path: String
    let name: String
    let depth: Int
    let children: [DiffTreeNode]

    var id: String { path }
}

nonisolated enum DiffTreeNode: Identifiable, Equatable, Sendable {
    case directory(DiffTreeDirectory)
    case file(DiffFile, depth: Int)

    var id: String {
        switch self {
        case let .directory(directory): directory.id
        case let .file(file, _): file.id
        }
    }

    var depth: Int {
        switch self {
        case let .directory(directory): directory.depth
        case let .file(_, depth): depth
        }
    }
}

nonisolated enum DiffTree {
    /// Groups a flat list of paths into folders, keeping the order the files arrive in.
    /// Within a level, directories come before the files that sit directly in it.
    static func build(files: [DiffFile]) -> [DiffTreeNode] {
        build(files: files, prefix: "", depth: 0)
    }

    private static func build(files: [DiffFile], prefix: String, depth: Int) -> [DiffTreeNode] {
        var directoryOrder: [String] = []
        var filesByDirectory: [String: [DiffFile]] = [:]
        var looseFiles: [DiffFile] = []

        for file in files {
            let remainder = file.path.dropFirst(prefix.count)
            let components = remainder.split(separator: "/")
            guard components.count > 1, let head = components.first.map(String.init) else {
                looseFiles.append(file)
                continue
            }
            if filesByDirectory[head] == nil {
                directoryOrder.append(head)
            }
            filesByDirectory[head, default: []].append(file)
        }

        var nodes: [DiffTreeNode] = directoryOrder.map { name in
            let path = prefix + name + "/"
            let children = build(files: filesByDirectory[name] ?? [], prefix: path, depth: depth + 1)
            return .directory(
                DiffTreeDirectory(path: path, name: name, depth: depth, children: children)
            )
        }
        nodes += looseFiles.map { .file($0, depth: depth) }
        return nodes
    }
}

/// A run of lines the reader dragged over, and how it is named in the popover and in
/// the chat message it produces.
nonisolated struct DiffSelection: Equatable, Sendable {
    let hunkID: String
    let fileName: String
    /// Indices into the hunk's lines, which is what the drag gesture works in.
    let rows: ClosedRange<Int>
    /// The displayed number of each selected line, in order.
    let lineNumbers: [Int]

    var lineCount: Int { rows.count }

    var lineCountLabel: String {
        lineCount == 1 ? "1 line" : "\(lineCount) lines"
    }

    /// "BillingGuard.swift:142" for one line, "InvoiceScheduler.swift:202–204" for a run.
    /// Two lines can share a number (a deletion and its replacement), so the label
    /// follows the numbers, not the row count.
    var location: String {
        guard let lowest = lineNumbers.min(), let highest = lineNumbers.max() else {
            return unnumberedLocation
        }
        guard highest > lowest else { return "\(fileName):\(lowest)" }
        return "\(fileName):\(lowest)\(DiffFormat.enDash)\(highest)"
    }

    /// What a selection is called when no line number can be read off it.
    var unnumberedLocation: String {
        "Selection · \(lineCountLabel)"
    }
}

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

/// Characters the interface uses that are not the ones on the keyboard.
nonisolated enum DiffFormat {
    /// U+2212, the minus that lines up with the digits — not a hyphen.
    static let minusSign = "\u{2212}"
    /// U+2013, the dash inside a line range.
    static let enDash = "\u{2013}"
}
