/// The vocabulary of one file's patch body: hunks, lines, and the runs of text
/// that carry an intra-line highlight. Pure values — nothing shells out from here.

nonisolated enum PatchLineKind: Equatable, Sendable {
    case context
    case addition
    case deletion
}

nonisolated struct PatchLineSegment: Equatable, Sendable {
    let text: String
    let isHighlighted: Bool

    init(text: String, isHighlighted: Bool = false) {
        self.text = text
        self.isHighlighted = isHighlighted
    }
}

nonisolated struct PatchLine: Equatable, Sendable {
    /// Absent on an addition: the line did not exist before the change.
    let oldNumber: Int?
    /// Absent on a deletion: the line does not exist after the change.
    let newNumber: Int?
    let kind: PatchLineKind
    let segments: [PatchLineSegment]

    var text: String {
        segments.map(\.text).joined()
    }
}

nonisolated struct PatchHunk: Equatable, Sendable {
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [PatchLine]
}
