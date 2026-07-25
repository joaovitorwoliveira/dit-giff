import SwiftUI

/// The center column: each file that carries a hunk, sticky headers, and the code itself.
/// A drag across lines opens the selection popover; a tap elsewhere clears it.
struct DiffViewer: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: DiffModel
    /// Set while a drag is choosing lines, so the viewer's "tap outside" clear does not
    /// erase the selection the drag just made.
    @State private var isSelectingLines = false

    var body: some View {
        // Vertical only: long lines wrap inside the viewport. With no horizontal axis,
        // `maxWidth: .infinity` resolves against the reader column again — cards, headers
        // and line fills share one width.
        //
        // Sidebar jumps use ScrollViewReader → scrollTo(headerID, anchor: .top).
        // The id lives on the sticky header (one per section file). LazyVStack can
        // resolve that id without materialising every code line between here and there.
        ScrollViewReader { scrollProxy in
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
                                .id(
                                    DiffFileNavigationResolver.scrollAnchorID(
                                        filePath: file.path
                                    )
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.horizontal, .s24)
                .dsPadding(.bottom, .s48)
            }
            .onChange(of: model.readerScrollRequest) { _, request in
                guard let request else { return }
                performReaderScroll(request, scrollProxy: scrollProxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface0)
        // A tap that is not eaten by a control or a drag clears the selection.
        .onTapGesture {
            guard !isSelectingLines else { return }
            model.clearSelection()
        }
    }

    private func performReaderScroll(
        _ request: DiffReaderScrollRequest,
        scrollProxy: ScrollViewProxy
    ) {
        let anchorID = DiffFileNavigationResolver.scrollAnchorID(filePath: request.path)
        if DiffReaderScrollRetry.isAnimated(attempt: request.attempt) {
            withAnimation(DSMotion.jump.animation(reduceMotion: reduceMotion)) {
                scrollProxy.scrollTo(anchorID, anchor: .top)
            }
        } else {
            scrollProxy.scrollTo(anchorID, anchor: .top)
        }

        guard let delay = DiffReaderScrollRetry.delayAfter(attempt: request.attempt) else {
            model.clearReaderScrollRequest()
            return
        }

        let nonce = request.nonce
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard model.readerScrollRequest?.nonce == nonce else { return }
            model.advanceReaderScrollRequest()
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
    /// Single-line row height — also the fallback for selection hit-testing before a
    /// wrapped row has reported its measured height.
    static let codeLineHeight: CGFloat = 20.15

    /// The `dg-sel-line` mark: a leading rule on every selected row.
    static let selectionBarWidth: CGFloat = 3

    /// Dimmed chrome for AI actions that have nothing to say yet (Slice 4).
    static let disabledOpacity: Double = 0.35

    /// SF Symbol point size inside the explain control — sits in the same 19pt frame
    /// the hand-drawn icon used.
    static let explainSparklesSize: CGFloat = 13
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
            DiffExplainFileButton(
                isEnabled: model.canExplainFile(file)
            ) {
                model.explainFile(file)
            }
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
        // Directory yields first and truncates at the *head* so the file name — the
        // identity of the row — stays whole. Never truncate the name with ellipsis.
        DSHStack(alignment: .firstTextBaseline, spacing: nil) {
            Text(file.directory)
                .font(DSTextStyle.body.font(fixedSize: DiffViewerMetric.directorySize))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.head)
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

    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: DiffViewerMetric.explainSparklesSize))
                .foregroundStyle(palette.textTertiary.color)
                .frame(
                    width: DiffIconMetric.explainFileSize,
                    height: DiffIconMetric.explainFileSize
                )
                .padding(DiffViewerMetric.iconButtonPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : DiffViewerMetric.disabledOpacity)
        .accessibilityLabel("Explain this file")
    }
}

private struct DiffViewedButton: View {
    @Environment(\.dsPalette) private var palette

    let isViewed: Bool
    let action: () -> Void

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
                    .lineLimit(1)
            }
            .foregroundStyle(
                isViewed ? palette.textPrimary.color : palette.textTertiary.color
            )
            .padding(.vertical, DiffViewerMetric.viewedVerticalPadding)
            .dsPadding(.horizontal, .s8)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                    .fill(isViewed ? palette.surface3.color : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
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
    private var fileLineCount: Int { DiffCodeMetrics.lineCount(in: file) }
    private var selectedHunkID: String? { model.selection?.hunkID }
    private var selectedRows: ClosedRange<Int>? { model.selection?.rows }

    var body: some View {
        Group {
            if !isCollapsed {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(file.hunks) { hunk in
                        DiffHunkBlock(
                            hunk: hunk,
                            model: model,
                            selectedRows: selectedHunkID == hunk.id ? selectedRows : nil,
                            showsSelectionPopover: selectedHunkID == hunk.id
                                && model.canPresentSelectionPopover,
                            isSelectingLines: $isSelectingLines
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            DiffCollapseAnimation.shouldAnimate(lineCount: fileLineCount)
                ? DSMotion.collapse.animation(reduceMotion: reduceMotion)
                : nil,
            value: isCollapsed
        )
    }
}

// MARK: - Hunk

private struct DiffHunkBlock: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hunk: DiffHunk
    let model: DiffModel
    /// Rows selected in this hunk, or `nil` when the selection is elsewhere.
    let selectedRows: ClosedRange<Int>?
    let showsSelectionPopover: Bool
    @Binding var isSelectingLines: Bool

    private var isRead: Bool { model.isRead(hunk) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                DiffHunkHeader(hunk: hunk, model: model)
                // Hover lives on the header only (inside DiffHunkHeader). Scrolling the
                // mouse across code lines must not thrash hunk chrome.
                DiffCodeGrid(
                    hunk: hunk,
                    selectedRows: selectedRows,
                    isSelectingLines: $isSelectingLines,
                    selectLines: { from, through in
                        model.selectLines(inHunkWithID: hunk.id, from: from, through: through)
                    }
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
        .overlay(alignment: .top) {
            // No agent ⇒ every popover action is dead. Prefer no popover over a corpse.
            if showsSelectionPopover {
                DiffSelectionPopover(model: model)
                    .alignmentGuide(.top) { $0[.bottom] + DSSpace.s8.points }
                    .zIndex(1)
            }
        }
        .dsPadding(.top, .s8)
    }
}

/// A short rail on the hunk's leading edge. Discrete on purpose: it is a clue that a
/// note exists, not a badge that ranks the change.
private struct DiffHunkNoteMarker: View {
    @Environment(\.dsPalette) private var palette

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
            .fill(palette.textTertiary.color)
            .frame(
                width: DiffViewerMetric.noteMarkerWidth,
                height: DiffViewerMetric.noteMarkerHeight
            )
            .padding(.top, DiffViewerMetric.noteMarkerTop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open analysis note")
    }
}

private struct DiffHunkHeader: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let hunk: DiffHunk
    let model: DiffModel

    var body: some View {
        DSHStack(spacing: .s8) {
            Text(hunk.header)
                .font(DSTextStyle.code.font(fixedSize: DiffViewerMetric.hunkHeaderSize))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            DiffHunkActions(hunk: hunk, model: model)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .dsPadding(.leading, .s12)
        .dsPadding(.trailing, .s8)
        .frame(height: DiffViewerMetric.hunkHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(height: DiffViewerMetric.hairline)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct DiffHunkActions: View {
    let hunk: DiffHunk
    let model: DiffModel

    private var canExplain: Bool { model.canExplain(hunk) }

    var body: some View {
        DSHStack(spacing: .s4) {
            DiffHunkIconButton(
                accessibilityLabel: "Explain this hunk",
                isEnabled: canExplain
            ) {
                model.explain(hunk)
            } label: {
                DiffHunkExplainIcon()
            }
            DiffHunkIconButton(
                accessibilityLabel: "Chat about this hunk",
                isEnabled: canExplain
            ) {
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

    let accessibilityLabel: String
    var isEnabled: Bool = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(palette.textTertiary.color)
                .padding(DiffViewerMetric.hunkActionPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : DiffViewerMetric.disabledOpacity)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DiffHunkReadButton: View {
    @Environment(\.dsPalette) private var palette

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
                isRead ? palette.textPrimary.color : palette.textTertiary.color
            )
            .padding(DiffViewerMetric.hunkActionPadding)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                    .fill(isRead ? palette.surface3.color : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRead ? "Mark hunk as unread" : "Mark hunk as read")
        .accessibilityAddTraits(isRead ? .isSelected : [])
    }
}

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

private struct DiffCodeGrid: View {
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
