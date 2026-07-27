import SwiftUI

struct DiffSidebarDirectoryRow: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let directory: DiffTreeDirectory
    let model: DiffModel

    private var isOpen: Bool {
        model.isDirectoryOpen(directory.path)
    }

    private var isFocused: Bool {
        model.isFocusedInSidebar(directory)
    }

    private var viewedState: DiffAggregateState {
        model.viewedState(for: directory)
    }

    /// All descendants viewed — marked background + quieter name. Partial is not dimmed.
    private var isDimmed: Bool {
        model.isDimmedInSidebar(directory)
    }

    var body: some View {
        Button {
            model.toggleDirectory(directory.path)
        } label: {
            DSHStack(spacing: .s4) {
                DiffChevronIcon()
                    .frame(
                        width: DiffSidebarMetric.chevronHitSize,
                        height: DiffSidebarMetric.chevronHitSize
                    )
                    .foregroundStyle(palette.textSecondary.color)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .animation(
                        DSMotion.collapse.animation(reduceMotion: reduceMotion),
                        value: isOpen
                    )
                DiffFolderIcon()
                    .foregroundStyle(palette.textPrimary.color)
                Text(directory.name)
                    .font(DSTextStyle.body.font(fixedSize: DiffSidebarMetric.nameSize))
                    .foregroundStyle(palette.textSecondary.color)
                    // Soft strike when every descendant is viewed — same cue as files.
                    .strikethrough(isDimmed, color: palette.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Reserved trailing slot — same width as the file viewed column so
                // marks share one right edge; the control sits in the overlay.
                Color.clear
                    .frame(
                        width: DiffSidebarMetric.viewedControlColumnWidth,
                        height: DiffSidebarMetric.folderControlHitSize
                    )
                    .accessibilityHidden(true)
            }
            // Opacity on the glyphs only — the surface2 fill below stays solid so the
            // row still reads as marked, not washed out.
            .opacity(isDimmed ? DSOpacity.read : 1)
            .padding(.leading, DiffSidebarMetric.rowLeadingInset(depth: directory.depth))
            .dsPadding(.trailing, .s8)
            .frame(height: DiffSidebarMetric.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(rowSurface, radius: .sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            // Overlay so the control is not inside the expand/collapse button. The
            // clear slot above keeps the name from running under the mark.
            DiffSidebarFolderViewedButton(state: viewedState) {
                model.toggleViewed(in: directory)
            }
            .dsPadding(.trailing, .s8)
            .opacity((isHovering || isDimmed) ? 1 : 0)
            .allowsHitTesting(isHovering || isDimmed)
        }
        .id(directory.path)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isOpen ? "Collapse \(directory.name)" : "Expand \(directory.name)")
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityValue(viewedAccessibilityValue)
    }

    private var rowSurface: DSColorValue {
        // Strongest → weakest: focused (keyboard) > hover > dimmed (viewed) > default.
        if isFocused { return palette.surfaceSelected }
        if isHovering { return palette.surfaceHover }
        if isDimmed { return palette.surface2 }
        return palette.surface1
    }

    private var viewedAccessibilityValue: String {
        switch viewedState {
        case .none: "None viewed"
        case .some: "Some viewed"
        case .all: "All viewed"
        }
    }
}

/// Marks or clears viewed on every descendant. Empty / dash / check match the file
/// Viewed control's checkbox vocabulary.
struct DiffSidebarFolderViewedButton: View {
    @Environment(\.dsPalette) private var palette

    let state: DiffAggregateState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DiffSidebarAggregateCheckbox(state: state)
                .foregroundStyle(
                    state == .none ? palette.textTertiary.color : palette.textPrimary.color
                )
                .frame(
                    width: DiffSidebarMetric.folderControlHitSize,
                    height: DiffSidebarMetric.folderControlHitSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(state == .all ? .isSelected : [])
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityLabel: String {
        state == .all ? "Mark folder as not viewed" : "Mark folder as viewed"
    }

    private var accessibilityValue: String {
        switch state {
        case .none: "None viewed"
        case .some: "Some viewed"
        case .all: "All viewed"
        }
    }
}

struct DiffSidebarAggregateCheckbox: View {
    @Environment(\.dsPalette) private var palette

    let state: DiffAggregateState

    var body: some View {
        ZStack {
            switch state {
            case .none:
                DiffCheckboxEmptyShape()
                    .stroke(lineWidth: DiffIconMetric.checkboxEmptyStroke)
            case .some:
                DiffCheckboxEmptyShape()
                    .stroke(lineWidth: DiffIconMetric.checkboxEmptyStroke)
                Capsule()
                    .fill(palette.textPrimary.color)
                    .frame(
                        width: DiffSidebarMetric.folderCheckboxDashWidth,
                        height: DiffSidebarMetric.folderCheckboxDashHeight
                    )
            case .all:
                DiffCheckboxFilledShape()
                    .fill()
                DiffCheckboxCheckShape()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: DiffIconMetric.fileCheckboxCheckStroke,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .foregroundStyle(palette.surface1.color)
            }
        }
        .frame(
            width: DiffIconMetric.fileCheckboxSize,
            height: DiffIconMetric.fileCheckboxSize
        )
    }
}
