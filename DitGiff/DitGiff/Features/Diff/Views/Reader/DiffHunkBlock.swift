import SwiftUI

// MARK: - File body

struct DiffFileBody: View {
    @Environment(\.dsPalette) private var palette
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
                    textBody
                        .diffFileCardBodyChrome(palette: palette)
                case .binary, .submodule, .noContent:
                    DiffNonTextFileBody(file: file)
                        .diffFileCardBodyChrome(palette: palette)
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

    private var textBody: some View {
        let showsHunkHeader = DiffHunkHeaderVisibility.showsHeader(
            hunkCount: file.hunks.count
        )
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(file.hunks.enumerated()), id: \.element.id) { index, hunk in
                DiffHunkBlock(
                    hunk: hunk,
                    model: model,
                    showsHeader: showsHunkHeader,
                    isFirst: index == 0,
                    isLast: index == file.hunks.count - 1,
                    selectedRows: selectedHunkID == hunk.id ? selectedRows : nil,
                    showsSelectionPopover: selectedHunkID == hunk.id
                        && model.canPresentSelectionPopover,
                    isSelectingLines: $isSelectingLines
                )
            }
        }
    }
}

// MARK: - Hunk

private struct DiffHunkBlock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hunk: DiffHunk
    let model: DiffModel
    /// From `DiffHunkHeaderVisibility` for the whole file — never a local hunk count.
    let showsHeader: Bool
    /// First hunk sits flush under the sticky file header; later ones draw a top rule.
    let isFirst: Bool
    /// Last hunk clips its content to the card's bottom corners so edge-to-edge line
    /// fills do not square past the chrome. The selection popover stays outside that clip.
    let isLast: Bool
    /// Rows selected in this hunk, or `nil` when the selection is elsewhere.
    let selectedRows: ClosedRange<Int>?
    let showsSelectionPopover: Bool
    @Binding var isSelectingLines: Bool

    private var isRead: Bool { model.isRead(hunk) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if showsHeader {
                    DiffHunkHeader(hunk: hunk, model: model, showsTopDivider: !isFirst)
                }
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
            .modifier(DiffHunkBottomCornerClip(isLast: isLast))

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
            // Lives outside DiffHunkBottomCornerClip so the popover can float above the
            // first lines without being cut by the card body.
            if showsSelectionPopover {
                DiffSelectionPopover(model: model)
                    .alignmentGuide(.top) { $0[.bottom] + DSSpace.s8.points }
                    .zIndex(1)
            }
        }
    }
}

/// Clips only the last hunk's header+grid to the file card's bottom radii. Applied to
/// content, never to the selection-popover overlay.
private struct DiffHunkBottomCornerClip: ViewModifier {
    let isLast: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isLast {
            content.clipShape(
                DiffFileCardChrome.shape(topRounded: false, bottomRounded: true)
            )
        } else {
            content
        }
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
    let showsTopDivider: Bool

    var body: some View {
        DSHStack(spacing: .s8) {
            Text(hunk.header)
                .font(DSTextStyle.code.font(fixedSize: DiffViewerMetric.hunkHeaderSize))
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            DiffHunkActions(hunk: hunk, model: model, isHovering: isHovering)
        }
        .dsPadding(.leading, .s12)
        .dsPadding(.trailing, .s8)
        .frame(height: DiffViewerMetric.hunkHeaderHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // surface2 so @@ reads as an internal divider, not another code row.
        .dsSurface(palette.surface2)
        .overlay(alignment: .top) {
            if showsTopDivider {
                Rectangle()
                    .fill(palette.borderSubtle.color)
                    .frame(height: DiffViewerMetric.hairline)
            }
        }
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
    let isHovering: Bool

    private var canExplain: Bool { model.canExplain(hunk) }
    private var isRead: Bool { model.isRead(hunk) }

    var body: some View {
        DSHStack(spacing: nil) {
            // Keep sparkles in the layout so Viewed does not shift when hover toggles.
            DiffHunkExplainButton(isEnabled: canExplain) {
                model.explain(hunk)
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            DiffHunkViewedButton(isRead: isRead) {
                model.toggleRead(hunk)
            }
        }
    }
}

private struct DiffHunkExplainButton: View {
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
        .accessibilityLabel("Explain this hunk")
    }
}

private struct DiffHunkViewedButton: View {
    @Environment(\.dsPalette) private var palette

    let isRead: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DiffViewerMetric.viewedCheckboxGap) {
                DiffCheckboxIcon(
                    isOn: isRead,
                    size: .file,
                    checkColor: palette.surface1
                )
                Text("Viewed")
                    .font(DSTextStyle.label.font(fixedSize: DiffViewerMetric.viewedLabelSize))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isRead ? palette.textPrimary.color : palette.textTertiary.color
            )
            .padding(.vertical, DiffViewerMetric.viewedVerticalPadding)
            .dsPadding(.horizontal, .s8)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                    .fill(isRead ? palette.surface3.color : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel(isRead ? "Mark hunk as not viewed" : "Mark hunk as viewed")
        .accessibilityAddTraits(isRead ? .isSelected : [])
    }
}
