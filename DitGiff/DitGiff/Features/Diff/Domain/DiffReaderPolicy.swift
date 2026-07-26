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

/// Characters the interface uses that are not the ones on the keyboard.
nonisolated enum DiffFormat {
    /// U+2212, the minus that lines up with the digits — not a hyphen.
    static let minusSign = "\u{2212}"
    /// U+2013, the dash inside a line range.
    static let enDash = "\u{2013}"
}

/// Stable identity for a diff row in the viewer. Offset-only ids collide across hunks
/// and lose correspondence when the line arrays are rebuilt.
nonisolated enum DiffLineIdentity {
    static func id(hunkID: String, rowIndex: Int) -> String {
        "\(hunkID):\(rowIndex)"
    }

    /// One row handle for `ForEach`, keyed by hunk id + row index.
    nonisolated struct RowID: Identifiable, Hashable, Sendable {
        let hunkID: String
        let rowIndex: Int

        var id: String { DiffLineIdentity.id(hunkID: hunkID, rowIndex: rowIndex) }
    }

    static func rowIDs(hunkID: String, lineCount: Int) -> [RowID] {
        (0..<lineCount).map { RowID(hunkID: hunkID, rowIndex: $0) }
    }
}

/// Collapse/expand of a file body animates every materialised row. Past this many
/// lines the animation costs more than it is worth, so the view skips it.
nonisolated enum DiffCollapseAnimation {
    static let maxLineCount = 120

    static func shouldAnimate(lineCount: Int) -> Bool {
        lineCount <= maxLineCount
    }
}

/// Pure counts over a file's hunk lines. Used for collapse-animation budget.
nonisolated enum DiffCodeMetrics {
    static func lineCount(in file: DiffFile) -> Int {
        file.hunks.reduce(0) { $0 + $1.lines.count }
    }
}

/// Where a sidebar file click should take the reader — or that the file is absent
/// from `sectionFiles` (sample stubs, or a text parse that produced no hunks).
nonisolated enum DiffFileNavigation: Equatable, Sendable {
    /// Scroll so this file's sticky header sits at the top of the viewport.
    case scrollToHeader(path: String)
    /// Present in the change map, absent from `sectionFiles`.
    case unavailableInReader(path: String)
}

/// Pure rules for sidebar → reader navigation. The view only animates what this decides.
nonisolated enum DiffFileNavigationResolver {
    /// Stable `ScrollViewReader` id for a file's sticky header. One id per section file —
    /// not per line — so jumping never requires materialising the LazyVStack of code.
    static func scrollAnchorID(filePath: String) -> String {
        "diff-file:\(filePath)"
    }

    static func resolve(
        filePath: String,
        sectionFilePaths: Set<String>
    ) -> DiffFileNavigation {
        if sectionFilePaths.contains(filePath) {
            return .scrollToHeader(path: filePath)
        }
        return .unavailableInReader(path: filePath)
    }

    /// Navigating to a collapsed file keeps it collapsed: the section header is still
    /// the scroll target and the identity the reader needs. Expanding would dump the
    /// body and erase the collapsed mark the reader already chose.
    static let expandsCollapsedFileOnNavigate = false
}

/// How many times the reader retries a sidebar jump after layout settles. Pure policy —
/// the view scrolls; this decides animation vs corrective passes and when to stop.
nonisolated enum DiffReaderScrollRetry {
    static let animatedAttempt = 0
    static let firstCorrectiveAttempt = 1
    static let finalAttempt = 2

    /// `DSMotion.jump` is 240ms; the first corrective pass waits for it to finish.
    static let delayAfterAnimatedAttempt: Duration = .milliseconds(300)
    static let delayAfterFirstCorrectiveAttempt: Duration = .milliseconds(120)

    static func isAnimated(attempt: Int) -> Bool {
        attempt == animatedAttempt
    }

    static func delayAfter(attempt: Int) -> Duration? {
        switch attempt {
        case animatedAttempt:
            return delayAfterAnimatedAttempt
        case firstCorrectiveAttempt:
            return delayAfterFirstCorrectiveAttempt
        default:
            return nil
        }
    }
}

/// One sidebar click that should scroll the reader. `nonce` makes a repeat click on the
/// same file observable to `onChange`; `attempt` indexes the retry sequence.
nonisolated struct DiffReaderScrollRequest: Equatable, Sendable {
    let path: String
    let nonce: UInt
    let attempt: Int
}

/// One chat click that should scroll the thread to an existing explanation. `nonce`
/// makes a repeat click on the same message observable to `onChange`.
nonisolated struct DiffChatScrollRequest: Equatable, Sendable {
    let messageID: Int
    let nonce: UInt
}

/// One code row's vertical span in the hunk grid's coordinate space.
nonisolated struct DiffCodeRowFrame: Equatable, Sendable {
    var minY: Double
    var height: Double

    var maxY: Double { minY + max(0, height) }
}

/// Maps a vertical drag position onto a code row when rows no longer share one height
/// (wrapped lines). Uses measured frames from materialised LazyVStack rows; gaps and
/// off-screen ranges step by `fallbackHeight` from the nearest measured neighbour.
nonisolated enum DiffCodeSelectionHitTesting {
    static func rowIndex(
        atY y: Double,
        frames: [Int: DiffCodeRowFrame],
        lineCount: Int,
        fallbackHeight: Double
    ) -> Int {
        guard lineCount > 0 else { return 0 }
        let step = max(fallbackHeight, 1)

        for (index, frame) in frames where y >= frame.minY && y < frame.maxY {
            return clamped(index, lineCount: lineCount)
        }

        guard !frames.isEmpty else {
            if y <= 0 { return 0 }
            return clamped(Int((y / step).rounded(.down)), lineCount: lineCount)
        }

        let ordered = frames.keys.sorted()
        if let first = ordered.first, let frame = frames[first], y < frame.minY {
            let steps = Int(((frame.minY - y) / step).rounded(.down)) + 1
            return clamped(first - steps, lineCount: lineCount)
        }
        if let last = ordered.last, let frame = frames[last], y >= frame.maxY {
            let steps = Int(((y - frame.maxY) / step).rounded(.down)) + 1
            return clamped(last + steps, lineCount: lineCount)
        }

        // Between two measured frames (a LazyVStack hole): walk from the lower neighbour.
        if let lower = ordered.last(where: { (frames[$0]?.maxY ?? 0) <= y }),
           let lowerFrame = frames[lower]
        {
            let steps = Int(((y - lowerFrame.maxY) / step).rounded(.down)) + 1
            return clamped(lower + steps, lineCount: lineCount)
        }

        return 0
    }

    private static func clamped(_ index: Int, lineCount: Int) -> Int {
        max(0, min(lineCount - 1, index))
    }
}
