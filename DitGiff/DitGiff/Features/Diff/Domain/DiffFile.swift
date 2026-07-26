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

/// What the reader draws for one file: hunk text, or a short non-text entry.
nonisolated enum DiffFileBodyKind: Equatable, Sendable {
    case text
    case binary
    case submodule(oldSHA: String?, newSHA: String?)
    case noContent

    /// One-line description in the reader. Descriptive, never a verdict.
    var readerSummary: String {
        switch self {
        case .binary:
            "Binary file. No text to show."
        case .submodule:
            "Submodule pointer changed."
        case .noContent:
            "No content in this patch."
        case .text:
            ""
        }
    }

    /// Extra line under the summary — submodule SHAs when git printed them.
    var readerDetail: String? {
        guard case let .submodule(oldSHA, newSHA) = self else { return nil }
        switch (oldSHA, newSHA) {
        case let (old?, new?):
            return "\(old) → \(new)"
        case let (nil, new?):
            return new
        case let (old?, nil):
            return old
        case (nil, nil):
            return nil
        }
    }
}

nonisolated struct DiffFile: Identifiable, Equatable, Sendable {
    let path: String
    let status: DiffFileStatus
    let additions: Int
    let deletions: Int
    let hunks: [DiffHunk]
    let body: DiffFileBodyKind

    init(
        path: String,
        status: DiffFileStatus,
        additions: Int,
        deletions: Int,
        hunks: [DiffHunk],
        body: DiffFileBodyKind = .text
    ) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.hunks = hunks
        self.body = body
    }

    var id: String { path }

    /// Text with hunks, or one of the three short-entry kinds. A `.text` file with
    /// empty hunks is a parsing bug — it is not treated as a special case.
    var belongsInReader: Bool {
        switch body {
        case .text:
            return !hunks.isEmpty
        case .binary, .submodule, .noContent:
            return true
        }
    }

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
