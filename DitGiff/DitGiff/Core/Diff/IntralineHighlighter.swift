/// Marks the middle that differs between a deleted line and an added line.
/// Common prefix and common suffix stay plain; when the lines share nothing,
/// the whole line is highlighted. Works on Swift `Character`s so accents and
/// emoji stay intact.

nonisolated struct IntralineHighlightResult: Equatable, Sendable {
    let deletion: [PatchLineSegment]
    let addition: [PatchLineSegment]
}

nonisolated enum IntralineHighlighter {
    static func highlight(deletion: String, addition: String) -> IntralineHighlightResult {
        let deleted = Array(deletion)
        let added = Array(addition)

        let prefixLength = commonPrefixLength(deleted, added)
        // Cap the suffix so prefix+suffix never exceed either side — otherwise
        // "aa"/"aaa" and "aba"/"abba" would overlap and slice out of range.
        let suffixLength = commonSuffixLength(
            deleted,
            added,
            excludingPrefix: prefixLength
        )

        let deletedMiddle = String(deleted[prefixLength..<(deleted.count - suffixLength)])
        let addedMiddle = String(added[prefixLength..<(added.count - suffixLength)])
        let prefix = String(deleted.prefix(prefixLength))
        let suffix = String(deleted.suffix(suffixLength))

        return IntralineHighlightResult(
            deletion: segments(prefix: prefix, middle: deletedMiddle, suffix: suffix),
            addition: segments(prefix: prefix, middle: addedMiddle, suffix: suffix)
        )
    }

    private static func commonPrefixLength(_ a: [Character], _ b: [Character]) -> Int {
        let limit = min(a.count, b.count)
        var index = 0
        while index < limit, a[index] == b[index] {
            index += 1
        }
        return index
    }

    private static func commonSuffixLength(
        _ a: [Character],
        _ b: [Character],
        excludingPrefix prefixLength: Int
    ) -> Int {
        let aRemaining = a.count - prefixLength
        let bRemaining = b.count - prefixLength
        let limit = min(aRemaining, bRemaining)
        var index = 0
        while index < limit, a[a.count - 1 - index] == b[b.count - 1 - index] {
            index += 1
        }
        return index
    }

    private static func segments(
        prefix: String,
        middle: String,
        suffix: String
    ) -> [PatchLineSegment] {
        var result: [PatchLineSegment] = []
        if !prefix.isEmpty {
            result.append(PatchLineSegment(text: prefix, isHighlighted: false))
        }
        if !middle.isEmpty {
            result.append(PatchLineSegment(text: middle, isHighlighted: true))
        }
        if !suffix.isEmpty {
            result.append(PatchLineSegment(text: suffix, isHighlighted: false))
        }
        if result.isEmpty {
            result.append(PatchLineSegment(text: "", isHighlighted: false))
        }
        return result
    }
}
