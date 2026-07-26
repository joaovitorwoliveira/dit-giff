import SwiftUI

// MARK: - File body

struct DiffFileBody: View {
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
                switch file.body {
                case .text:
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
                case .binary, .submodule, .noContent:
                    DiffNonTextFileBody(file: file)
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
