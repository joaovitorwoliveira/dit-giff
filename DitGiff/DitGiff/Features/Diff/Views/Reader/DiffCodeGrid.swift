import SwiftUI

// MARK: - Code grid

/// Vertical spans of materialised code rows, keyed by row index, in the hunk grid's
/// named coordinate space. Lazy holes are absent; hit-testing steps from neighbours.
private struct DiffCodeRowFramesKey: PreferenceKey {
    static let defaultValue: [Int: DiffCodeRowFrame] = [:]

    static func reduce(
        value: inout [Int: DiffCodeRowFrame],
        nextValue: () -> [Int: DiffCodeRowFrame]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum DiffCodeGridSpace {
    static let name = "diff.codeGrid"
}

/// Row frames for selection hit-testing — reference storage so preference updates
/// do not re-render the grid on every layout pass.
@MainActor
private final class DiffCodeRowFramesStore {
    private(set) var frames: [Int: DiffCodeRowFrame] = [:]

    func updateIfNeeded(_ newFrames: [Int: DiffCodeRowFrame]) {
        guard newFrames != frames else { return }
        frames = newFrames
    }

    func reset() {
        frames = [:]
    }
}

struct DiffCodeGrid: View {
    @Environment(\.diffHunkRenderCache) private var renderCache

    let hunk: DiffHunk
    let selectedRows: ClosedRange<Int>?
    @Binding var isSelectingLines: Bool
    let selectLines: (_ from: Int, _ through: Int) -> Void

    @State private var dragOrigin: Int?
    @State private var framesStore = DiffCodeRowFramesStore()

    var body: some View {
        // Lookup stays in body (not init) so struct recreation does not re-lex. When
        // DiffViewer injects the cache, memoization applies; without it we compute directly.
        let syntaxSpans = resolvedSyntaxSpans
        let rowIDs = resolvedRowIDs
        // Lazy at the line level: materialising every row of a large hunk is what
        // froze scrolling when only the file stack was lazy.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rowIDs) { rowID in
                DiffCodeLineRow(
                    line: hunk.lines[rowID.rowIndex],
                    syntaxSpans: syntaxSpans[rowID.rowIndex],
                    rowIndex: rowID.rowIndex,
                    isSelected: selectedRows?.contains(rowID.rowIndex) ?? false,
                    measureFrame: isSelectingLines
                )
            }
        }
        .coordinateSpace(name: DiffCodeGridSpace.name)
        .onPreferenceChange(DiffCodeRowFramesKey.self) { newFrames in
            framesStore.updateIfNeeded(newFrames)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(selectionDrag)
        .dsPadding(.vertical, .s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedSyntaxSpans: [[SyntaxSpan]] {
        if let renderCache {
            return renderCache.syntaxSpans(for: hunk)
        }
        return DiffSyntaxAdapter.syntaxSpans(for: hunk)
    }

    private var resolvedRowIDs: [DiffLineIdentity.RowID] {
        if let renderCache {
            return renderCache.rowIDs(for: hunk)
        }
        return DiffLineIdentity.rowIDs(hunkID: hunk.id, lineCount: hunk.lines.count)
    }

    private var selectionDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(DiffCodeGridSpace.name))
            .onChanged { value in
                isSelectingLines = true
                let index = DiffCodeSelectionHitTesting.rowIndex(
                    atY: Double(value.location.y),
                    frames: framesStore.frames,
                    lineCount: hunk.lines.count,
                    fallbackHeight: Double(DiffViewerMetric.codeLineHeight)
                )
                if dragOrigin == nil {
                    dragOrigin = index
                }
                guard let origin = dragOrigin else { return }
                selectLines(origin, index)
            }
            .onEnded { _ in
                dragOrigin = nil
                framesStore.reset()
                // Let the viewer's tap-to-clear see the flag for one turn after the drag.
                DispatchQueue.main.async {
                    isSelectingLines = false
                }
            }
    }
}

private struct DiffCodeLineRow: View {
    @Environment(\.dsPalette) private var palette

    let line: DiffLine
    let syntaxSpans: [SyntaxSpan]
    let rowIndex: Int
    let isSelected: Bool
    let measureFrame: Bool

    var body: some View {
        // Top-aligned gutter: when the code wraps, numbers and the sign stay on the
        // first visual line only; continuation rows keep an empty gutter of the same
        // width so columns stay aligned.
        HStack(alignment: .top, spacing: 0) {
            lineNumber(line.oldNumber, width: DiffViewerMetric.oldLineNumberWidth)
            lineNumber(line.newNumber, width: DiffViewerMetric.newLineNumberWidth)
            Text(line.kind.sign)
                .frame(
                    width: DiffViewerMetric.signWidth,
                    height: DiffViewerMetric.codeLineHeight,
                    alignment: .center
                )
                .foregroundStyle(signColor.color)
            Text(attributedCode)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.trailing, .s24)
                .multilineTextAlignment(.leading)
        }
        .font(DSTextStyle.code.font(fixedSize: DiffViewerMetric.codeSize))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: DiffViewerMetric.codeLineHeight, alignment: .top)
        .background(rowBackground?.color ?? Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(palette.diffAdd.color)
                    .frame(width: DiffViewerMetric.selectionBarWidth)
            }
        }
        .background {
            if measureFrame {
                GeometryReader { geo in
                    let frame = geo.frame(in: .named(DiffCodeGridSpace.name))
                    Color.clear.preference(
                        key: DiffCodeRowFramesKey.self,
                        value: [
                            rowIndex: DiffCodeRowFrame(
                                minY: Double(frame.minY),
                                height: Double(frame.height)
                            ),
                        ]
                    )
                }
            }
        }
    }

    private func lineNumber(_ number: Int?, width: CGFloat) -> some View {
        Text(number.map(String.init) ?? "")
            .dsText(.lineNumber)
            .foregroundStyle(palette.textTertiary.color)
            .lineLimit(1)
            .frame(
                width: width,
                height: DiffViewerMetric.codeLineHeight,
                alignment: .trailing
            )
            .dsPadding(.trailing, .s8)
    }

    /// One `Text` for the whole line. Base colour comes from the diff line kind; syntax
    /// spans override foreground only so word-diff backgrounds from segments stay put.
    private var attributedCode: AttributedString {
        var result = AttributedString()
        let foreground = codeColor.color
        for segment in line.segments {
            var run = AttributedString(segment.text)
            run.foregroundColor = foreground
            if let fill = segmentBackground(segment) {
                run.backgroundColor = fill.color
            }
            result += run
        }
        applySyntaxSpans(to: &result)
        return result
    }

    private func applySyntaxSpans(to result: inout AttributedString) {
        let lineLength = line.text.count
        let dimSyntax = line.kind == .context

        for span in syntaxSpans {
            guard span.length > 0,
                  span.start >= 0,
                  span.start + span.length <= lineLength,
                  let range = characterRange(in: result, start: span.start, length: span.length)
            else { continue }

            result[range].foregroundColor = syntaxColor(for: span.kind, dimmed: dimSyntax)
        }
    }

    private func characterRange(
        in string: AttributedString,
        start: Int,
        length: Int
    ) -> Range<AttributedString.Index>? {
        guard start >= 0, length > 0 else { return nil }
        let end = start + length
        guard end <= string.characters.count else { return nil }

        let startIndex = string.index(string.startIndex, offsetByCharacters: start)
        let endIndex = string.index(startIndex, offsetByCharacters: length)
        return startIndex..<endIndex
    }

    private func syntaxColor(for kind: SyntaxTokenKind, dimmed: Bool) -> Color {
        let base: DSColorValue
        switch kind {
        case .keyword: base = palette.syntax.keyword
        case .type: base = palette.syntax.type
        case .string: base = palette.syntax.string
        case .number: base = palette.syntax.number
        case .comment: base = palette.syntax.comment
        case .function, .decorator: base = palette.syntax.function
        case .punctuation: base = palette.syntax.punctuation
        }
        let value = dimmed ? base.withOpacity(DSOpacity.syntaxContext) : base
        return value.color
    }

    private var rowBackground: DSColorValue? {
        switch line.kind {
        case .context: nil
        case .addition: palette.diffAddBackground
        case .deletion: palette.diffDelBackground
        }
    }

    private var signColor: DSColorValue {
        switch line.kind {
        case .context: palette.textSecondary
        case .addition: palette.diffAdd
        case .deletion: palette.diffDel
        }
    }

    private var codeColor: DSColorValue {
        switch line.kind {
        case .context: palette.textSecondary
        case .addition, .deletion: palette.textPrimary
        }
    }

    private func segmentBackground(_ segment: DiffLineSegment) -> DSColorValue? {
        guard segment.isHighlighted else { return nil }
        switch line.kind {
        case .addition: return palette.diffAddWord
        case .deletion: return palette.diffDelWord
        case .context: return nil
        }
    }
}
