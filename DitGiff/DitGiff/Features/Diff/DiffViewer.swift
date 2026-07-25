import SwiftUI

/// The center column: each file that carries a hunk, sticky headers, and the code itself.
/// A drag across lines opens the selection popover; a tap elsewhere clears it.
struct DiffViewer: View {
    @Environment(\.dsPalette) private var palette

    let model: DiffModel
    /// Set while a drag is choosing lines, so the viewer's "tap outside" clear does not
    /// erase the selection the drag just made.
    @State private var isSelectingLines = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(model.sectionFiles) { file in
                    Section {
                        DiffFileBody(
                            file: file,
                            model: model,
                            isSelectingLines: $isSelectingLines
                        )
                    } header: {
                        DiffFileStickyHeader(file: file, model: model)
                            .dsPadding(.top, .s16)
                    }
                }
            }
            .dsPadding(.horizontal, .s24)
            .dsPadding(.bottom, .s48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface0)
        // A tap that is not eaten by a control or a drag clears the selection.
        .onTapGesture {
            guard !isSelectingLines else { return }
            model.clearSelection()
        }
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
private enum DiffViewerMetric {
    static let hairline: CGFloat = 1

    static let headerHeight: CGFloat = 48
    static let chevronHitSize: CGFloat = 16
    static let directorySize: CGFloat = 12.5
    static let fileNameSize: CGFloat = 14
    static let statsSize: CGFloat = 11
    static let iconButtonPadding: CGFloat = 6
    static let viewedVerticalPadding: CGFloat = 6
    static let viewedCheckboxGap: CGFloat = 6
    static let viewedLabelSize: CGFloat = 13

    static let hunkHeaderHeight: CGFloat = 28
    static let hunkHeaderSize: CGFloat = 11
    static let hunkActionPadding: CGFloat = 3

    /// The analysis-note clue on the hunk's leading edge — same rail the v1 prototype used.
    static let noteMarkerWidth: CGFloat = 3
    static let noteMarkerHeight: CGFloat = 16
    static let noteMarkerTop: CGFloat = 6
    static let noteMarkerRadius: CGFloat = 2

    static let oldLineNumberWidth: CGFloat = 36
    static let newLineNumberWidth: CGFloat = 28
    static let signWidth: CGFloat = 16
    static let codeSize: CGFloat = 13
    static let codeLineHeight: CGFloat = 20.15

    /// The `dg-sel-line` mark: a leading rule on every selected row.
    static let selectionBarWidth: CGFloat = 3
}

// MARK: - Sticky file header

private struct DiffFileStickyHeader: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let file: DiffFile
    let model: DiffModel

    private var isOpen: Bool { !model.isCollapsed(file) }
    private var isViewed: Bool { model.isViewed(file) }

    var body: some View {
        DSHStack(spacing: .s8) {
            collapseButton
            pathLabel
            counters
            DiffExplainFileButton { model.explainFile(file) }
            DiffViewedButton(isViewed: isViewed) { model.toggleViewed(file) }
        }
        .dsPadding(.leading, .s8)
        .dsPadding(.trailing, .s12)
        .frame(height: DiffViewerMetric.headerHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(palette.surface1, radius: .md)
        .dsBorder(palette.borderSubtle, radius: .md)
    }

    private var collapseButton: some View {
        Button {
            model.toggleCollapsed(file)
        } label: {
            DiffChevronIcon()
                .foregroundStyle(palette.textTertiary.color)
                .frame(
                    width: DiffViewerMetric.chevronHitSize,
                    height: DiffViewerMetric.chevronHitSize
                )
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .animation(
                    DSMotion.collapse.animation(reduceMotion: reduceMotion),
                    value: isOpen
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Collapse \(file.name)" : "Expand \(file.name)")
    }

    private var pathLabel: some View {
        DSHStack(alignment: .firstTextBaseline, spacing: nil) {
            Text(file.directory)
                .font(DSTextStyle.body.font(fixedSize: DiffViewerMetric.directorySize))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Text(file.name)
                .font(DSTextStyle.panelTitle.font(fixedSize: DiffViewerMetric.fileNameSize))
                .foregroundStyle(palette.textPrimary.color)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var counters: some View {
        DSHStack(spacing: .s4) {
            Text(file.additionsLabel)
                .foregroundStyle(palette.diffAdd.color)
            Text(file.deletionsLabel)
                .foregroundStyle(palette.diffDel.color)
        }
        .font(DSTextStyle.code.font(fixedSize: DiffViewerMetric.statsSize))
        .lineLimit(1)
    }
}

private struct DiffExplainFileButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DiffExplainFileIcon()
                .foregroundStyle(
                    isHovering ? palette.textPrimary.color : palette.textTertiary.color
                )
                .padding(DiffViewerMetric.iconButtonPadding)
                .background {
                    RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                        .fill(isHovering ? palette.surface3.color : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Explain this file")
    }
}

private struct DiffViewedButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let isViewed: Bool
    let action: () -> Void

    private var showsFilledChrome: Bool { isViewed || isHovering }

    var body: some View {
        Button(action: action) {
            // Gap 6 is off the closed scale, so this stack takes the metric directly.
            HStack(spacing: DiffViewerMetric.viewedCheckboxGap) {
                DiffCheckboxIcon(
                    isOn: isViewed,
                    size: .file,
                    checkColor: palette.surface1
                )
                Text("Viewed")
                    .font(DSTextStyle.label.font(fixedSize: DiffViewerMetric.viewedLabelSize))
            }
            .foregroundStyle(
                showsFilledChrome ? palette.textPrimary.color : palette.textTertiary.color
            )
            .padding(.vertical, DiffViewerMetric.viewedVerticalPadding)
            .dsPadding(.horizontal, .s8)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                    .fill(showsFilledChrome ? palette.surface3.color : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isViewed ? "Mark as not viewed" : "Mark as viewed")
        .accessibilityAddTraits(isViewed ? .isSelected : [])
    }
}

// MARK: - File body

private struct DiffFileBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let file: DiffFile
    let model: DiffModel
    @Binding var isSelectingLines: Bool

    private var isCollapsed: Bool { model.isCollapsed(file) }

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            if !isCollapsed {
                ForEach(file.hunks) { hunk in
                    DiffHunkBlock(
                        hunk: hunk,
                        model: model,
                        isSelectingLines: $isSelectingLines
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            DSMotion.collapse.animation(reduceMotion: reduceMotion),
            value: isCollapsed
        )
    }
}

// MARK: - Hunk

private struct DiffHunkBlock: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let hunk: DiffHunk
    let model: DiffModel
    @Binding var isSelectingLines: Bool

    private var isRead: Bool { model.isRead(hunk) }
    private var isSelectedHunk: Bool { model.selection?.hunkID == hunk.id }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                DiffHunkHeader(hunk: hunk, model: model, actionsVisible: isHovering)
                DiffCodeGrid(
                    hunk: hunk,
                    model: model,
                    isSelectingLines: $isSelectingLines
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(palette.surface1, radius: .md)
            .dsBorder(palette.borderSubtle, radius: .md)
            .dsClip(.md)

            if hunk.note != nil {
                DiffHunkNoteMarker { model.openNote(hunk) }
            }
        }
        .opacity(isRead ? DSOpacity.read : 1)
        .animation(
            DSMotion.read.animation(reduceMotion: reduceMotion),
            value: isRead
        )
        // Anchored above the hunk, not above the selected rows: precise line-relative
        // placement fights the nested scroll views, and simple+correct wins here.
        .overlay(alignment: .top) {
            if isSelectedHunk {
                DiffSelectionPopover(model: model)
                    .alignmentGuide(.top) { $0[.bottom] + DSSpace.s8.points }
                    .zIndex(1)
            }
        }
        .dsPadding(.top, .s8)
        .onHover { isHovering = $0 }
    }
}

/// A short rail on the hunk's leading edge. Discrete on purpose: it is a clue that a
/// note exists, not a badge that ranks the change.
private struct DiffHunkNoteMarker: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: DiffViewerMetric.noteMarkerRadius,
                topTrailingRadius: DiffViewerMetric.noteMarkerRadius,
                style: .continuous
            )
            .fill(
                isHovering ? palette.textSecondary.color : palette.textTertiary.color
            )
            .frame(
                width: DiffViewerMetric.noteMarkerWidth,
                height: DiffViewerMetric.noteMarkerHeight
            )
            .padding(.top, DiffViewerMetric.noteMarkerTop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Open analysis note")
    }
}

private struct DiffHunkHeader: View {
    @Environment(\.dsPalette) private var palette

    let hunk: DiffHunk
    let model: DiffModel
    let actionsVisible: Bool

    var body: some View {
        DSHStack(spacing: .s8) {
            Text(hunk.header)
                .font(DSTextStyle.code.font(fixedSize: DiffViewerMetric.hunkHeaderSize))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            DiffHunkActions(hunk: hunk, model: model)
                .opacity(actionsVisible ? 1 : 0)
                .allowsHitTesting(actionsVisible)
        }
        .dsPadding(.leading, .s12)
        .dsPadding(.trailing, .s8)
        .frame(height: DiffViewerMetric.hunkHeaderHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(height: DiffViewerMetric.hairline)
        }
    }
}

private struct DiffHunkActions: View {
    let hunk: DiffHunk
    let model: DiffModel

    var body: some View {
        DSHStack(spacing: .s4) {
            DiffHunkIconButton(accessibilityLabel: "Explain this hunk") {
                model.explain(hunk)
            } label: {
                DiffHunkExplainIcon()
            }
            DiffHunkIconButton(accessibilityLabel: "Chat about this hunk") {
                // Same entry as explain until the chat panel grows its own verb.
                model.explain(hunk)
            } label: {
                DiffHunkChatIcon()
            }
            DiffHunkReadButton(isRead: model.isRead(hunk)) {
                model.toggleRead(hunk)
            }
        }
    }
}

private struct DiffHunkIconButton<Label: View>: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(
                    isHovering ? palette.textPrimary.color : palette.textTertiary.color
                )
                .padding(DiffViewerMetric.hunkActionPadding)
                .background {
                    RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                        .fill(isHovering ? palette.surface3.color : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DiffHunkReadButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let isRead: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DiffCheckboxIcon(
                isOn: isRead,
                size: .hunk,
                checkColor: palette.surface1
            )
            .foregroundStyle(
                isHovering || isRead ? palette.textPrimary.color : palette.textTertiary.color
            )
            .padding(DiffViewerMetric.hunkActionPadding)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                    .fill(isHovering || isRead ? palette.surface3.color : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isRead ? "Mark hunk as unread" : "Mark hunk as read")
        .accessibilityAddTraits(isRead ? .isSelected : [])
    }
}

// MARK: - Code grid

/// The code column is monospaced, so the widest row is simply the one with the most
/// characters and its width can be measured once. Measuring is what keeps the layout
/// system out of a negotiation it cannot settle.
private enum DiffCodeWidth {
    /// The advance of one character, taken from the face the diff actually renders in so
    /// the measurement matches what is drawn.
    private static let advance: CGFloat = {
        let size = DiffViewerMetric.codeSize
        let font = DSCodeFont.isAvailable
            ? NSFont(name: DSCodeFont.faceName(for: .regular), size: size)
            : nil
        let resolved = font ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        return "0".size(withAttributes: [.font: resolved]).width
    }()

    static func widest(of lines: [DiffLine]) -> CGFloat {
        let characters = lines.map(\.text.count).max() ?? 0
        return CGFloat(characters) * advance
    }
}

private struct DiffCodeGrid: View {
    let hunk: DiffHunk
    let model: DiffModel
    @Binding var isSelectingLines: Bool

    @State private var dragOrigin: Int?

    /// Every row is given the same measured width so the add and delete fills line up on
    /// the right. It is measured rather than negotiated: asking `fixedSize` for an ideal
    /// width while the rows inside ask for `maxWidth: .infinity` is a contradiction, and
    /// SwiftUI resolves it by re-sizing forever — it hung the window when a maximised
    /// screen collapsed a file.
    private var codeWidth: CGFloat {
        DiffCodeWidth.widest(of: hunk.lines)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { index, line in
                    DiffCodeLineRow(
                        line: line,
                        isSelected: isSelected(index),
                        codeWidth: codeWidth
                    )
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(selectionDrag)
            .dsPadding(.vertical, .s4)
        }
    }

    private var selectionDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isSelectingLines = true
                let index = Int(floor(value.location.y / DiffViewerMetric.codeLineHeight))
                if dragOrigin == nil {
                    dragOrigin = index
                }
                guard let origin = dragOrigin else { return }
                model.selectLines(inHunkWithID: hunk.id, from: origin, through: index)
            }
            .onEnded { _ in
                dragOrigin = nil
                // Let the viewer's tap-to-clear see the flag for one turn after the drag.
                DispatchQueue.main.async {
                    isSelectingLines = false
                }
            }
    }

    private func isSelected(_ index: Int) -> Bool {
        guard let selection = model.selection, selection.hunkID == hunk.id else {
            return false
        }
        return selection.rows.contains(index)
    }
}

private struct DiffCodeLineRow: View {
    @Environment(\.dsPalette) private var palette

    let line: DiffLine
    let isSelected: Bool
    let codeWidth: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            lineNumber(line.oldNumber, width: DiffViewerMetric.oldLineNumberWidth)
            lineNumber(line.newNumber, width: DiffViewerMetric.newLineNumberWidth)
            Text(line.kind.sign)
                .frame(width: DiffViewerMetric.signWidth, alignment: .center)
                .foregroundStyle(signColor.color)
            codeSegments
                // `minWidth`, not `width`: if the measurement ever falls a hair short of
                // what the text needs, the longest row grows instead of clipping.
                .frame(minWidth: codeWidth, alignment: .leading)
                .dsPadding(.trailing, .s24)
        }
        .font(DSTextStyle.code.font(fixedSize: DiffViewerMetric.codeSize))
        .frame(height: DiffViewerMetric.codeLineHeight, alignment: .top)
        .background(rowBackground?.color ?? Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(palette.diffAdd.color)
                    .frame(width: DiffViewerMetric.selectionBarWidth)
            }
        }
    }

    private func lineNumber(_ number: Int?, width: CGFloat) -> some View {
        Text(number.map(String.init) ?? "")
            .dsText(.lineNumber)
            .foregroundStyle(palette.textTertiary.color)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .dsPadding(.trailing, .s8)
            .frame(width: width, alignment: .trailing)
    }

    private var codeSegments: some View {
        // One Text per segment so a word highlight can paint only its own run.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(line.segments.enumerated()), id: \.offset) { _, segment in
                Text(segment.text)
                    .foregroundStyle(codeColor.color)
                    .background(segmentBackground(segment)?.color ?? Color.clear)
            }
        }
        .lineLimit(1)
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

// MARK: - Previews

#Preview("Viewer — dark") {
    DiffViewer(model: DiffModel())
        .frame(width: DiffLayout.minimumViewerWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.dark)
}

#Preview("Viewer — light") {
    DiffViewer(model: DiffModel())
        .frame(width: DiffLayout.minimumViewerWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.light)
}
