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

struct DiffCodeGrid: View {
    let hunk: DiffHunk
    let selectedRows: ClosedRange<Int>?
    @Binding var isSelectingLines: Bool
    let selectLines: (_ from: Int, _ through: Int) -> Void

    @State private var dragOrigin: Int?
    @State private var measuredFrames: [Int: DiffCodeRowFrame] = [:]

    /// Built once when the grid value is created — not on every `body` read.
    private let rowIDs: [DiffLineIdentity.RowID]

    init(
        hunk: DiffHunk,
        selectedRows: ClosedRange<Int>?,
        isSelectingLines: Binding<Bool>,
        selectLines: @escaping (_ from: Int, _ through: Int) -> Void
    ) {
        self.hunk = hunk
        self.selectedRows = selectedRows
        self._isSelectingLines = isSelectingLines
        self.selectLines = selectLines
        self.rowIDs = DiffLineIdentity.rowIDs(hunkID: hunk.id, lineCount: hunk.lines.count)
    }

    var body: some View {
        // Lazy at the line level: materialising every row of a large hunk is what
        // froze scrolling when only the file stack was lazy.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rowIDs) { rowID in
                DiffCodeLineRow(
                    line: hunk.lines[rowID.rowIndex],
                    rowIndex: rowID.rowIndex,
                    isSelected: selectedRows?.contains(rowID.rowIndex) ?? false
                )
            }
        }
        .coordinateSpace(name: DiffCodeGridSpace.name)
        .onPreferenceChange(DiffCodeRowFramesKey.self) { measuredFrames = $0 }
        .contentShape(Rectangle())
        .highPriorityGesture(selectionDrag)
        .dsPadding(.vertical, .s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(DiffCodeGridSpace.name))
            .onChanged { value in
                isSelectingLines = true
                let index = DiffCodeSelectionHitTesting.rowIndex(
                    atY: Double(value.location.y),
                    frames: measuredFrames,
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
    let rowIndex: Int
    let isSelected: Bool

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

    /// One `Text` for the whole line. Highlighted segments become attributed runs with
    /// the same foreground and word-fill colours the per-segment `Text`s used before.
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
        return result
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
