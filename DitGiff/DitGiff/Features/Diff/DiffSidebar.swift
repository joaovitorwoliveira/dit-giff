import SwiftUI

/// The change map: how far the reader has got, which files belong to the diff, and a
/// filter that keeps the tree honest about what still matches.
struct DiffSidebar: View {
    @Environment(\.dsPalette) private var palette

    @Bindable var model: DiffModel

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            DiffSidebarHeader(model: model)
            DiffSidebarFilter(model: model)
            DiffSidebarTree(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dsSurface(palette.surface1)
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
private enum DiffSidebarMetric {
    static let hairline: CGFloat = 1

    static let branchSize: CGFloat = 11
    static let nameSize: CGFloat = 13
    static let counterSize: CGFloat = 11

    static let progressHeight: CGFloat = 3
    static let progressRadius: CGFloat = 2

    static let filterHeight: CGFloat = 26

    static let rowHeight: CGFloat = 32
    static let chevronHitSize: CGFloat = 14
    static let counterMinWidth: CGFloat = 32

    static let rowIndentBase: CGFloat = 8
    static let rowIndentPerDepth: CGFloat = 16

    static let folderControlHitSize: CGFloat = 22
    static let folderCheckboxDashHeight: CGFloat = 2
    static let folderCheckboxDashWidth: CGFloat = 8

    static func rowLeadingInset(depth: Int) -> CGFloat {
        rowIndentBase + CGFloat(depth) * rowIndentPerDepth
    }
}

// MARK: - Header

private struct DiffSidebarHeader: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: DiffModel

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            branchLine
            Text(model.progressText)
                .dsText(.label)
                .foregroundStyle(palette.textSecondary.color)
            progressBar
            if model.allRead {
                Text("All read — ready to open the MR.")
                    .dsText(.label)
                    .foregroundStyle(palette.textPrimary.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPadding(.all, .s12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(height: DiffSidebarMetric.hairline)
        }
    }

    private var branchLine: some View {
        DSVStack(alignment: .leading, spacing: .s4) {
            if !model.repositoryName.isEmpty {
                Text(model.repositoryName)
                    .font(DSTextStyle.code.font(fixedSize: DiffSidebarMetric.nameSize))
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            DSHStack(spacing: .s4) {
                Text(model.compareBranch)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Compare yields first when the pair is too wide; the base stays whole.
                    .layoutPriority(-1)
                Text("→")
                    .layoutPriority(1)
                Text(model.baseBranch)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(DSTextStyle.code.font(fixedSize: DiffSidebarMetric.branchSize))
            .foregroundStyle(palette.textSecondary.color)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DiffSidebarMetric.progressRadius, style: .continuous)
                    .fill(palette.surface3.color)
                RoundedRectangle(cornerRadius: DiffSidebarMetric.progressRadius, style: .continuous)
                    .fill(palette.textTertiary.color)
                    .frame(width: geometry.size.width * model.progressFraction)
            }
        }
        .frame(height: DiffSidebarMetric.progressHeight)
        .animation(
            DSMotion.read.animation(reduceMotion: reduceMotion),
            value: model.progressFraction
        )
    }
}

// MARK: - Filter

private struct DiffSidebarFilter: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var model: DiffModel
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            text: $model.filter,
            prompt: Text("Filter files…")
                .foregroundStyle(palette.textTertiary.color)
        ) {
            Text("Filter files…")
        }
        .textFieldStyle(.plain)
        // AppKit renders a TextField's label beside the control unless it is hidden, which
        // would put a second "Filter files…" next to the placeholder.
        .labelsHidden()
        .dsText(.label)
        .foregroundStyle(palette.textPrimary.color)
        .focused($isFocused)
        .focusEffectDisabled()
        .dsPadding(.horizontal, .s8)
        .frame(height: DiffSidebarMetric.filterHeight)
        .frame(maxWidth: .infinity)
        .dsSurface(palette.surface2, radius: .sm)
        .dsBorder(palette.border, radius: .sm)
        .dsFocusRing(isFocused, radius: .sm)
        .dsPadding(.horizontal, .s8)
        .dsPadding(.top, .s8)
    }
}

// MARK: - Tree

private struct DiffSidebarTree: View {
    @Environment(\.dsPalette) private var palette

    let model: DiffModel

    var body: some View {
        ScrollView {
            DSVStack(alignment: .leading, spacing: nil) {
                if model.fileTree.isEmpty {
                    emptyState
                } else {
                    DiffSidebarTreeNodes(nodes: model.fileTree, model: model)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPadding(.horizontal, .s8)
            .dsPadding(.top, .s8)
            .dsPadding(.bottom, .s24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The prototype leaves a blank list when the filter matches nothing. A short label
    /// is clearer than a silent empty scroll area: the reader knows the filter is
    /// working, not that the tree failed to load.
    private var emptyState: some View {
        Text("No files match.")
            .dsText(.label)
            .foregroundStyle(palette.textTertiary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPadding(.horizontal, .s8)
            .dsPadding(.vertical, .s8)
    }
}

private struct DiffSidebarTreeNodes: View {
    let nodes: [DiffTreeNode]
    let model: DiffModel

    var body: some View {
        ForEach(nodes) { node in
            switch node {
            case let .directory(directory):
                DiffSidebarDirectoryBranch(directory: directory, model: model)
            case let .file(file, depth):
                DiffSidebarFileRow(file: file, depth: depth, model: model)
            }
        }
    }
}

private struct DiffSidebarDirectoryBranch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let directory: DiffTreeDirectory
    let model: DiffModel

    private var isOpen: Bool {
        model.isDirectoryOpen(directory.path)
    }

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            DiffSidebarDirectoryRow(directory: directory, model: model)
            if isOpen {
                DiffSidebarTreeNodes(nodes: directory.children, model: model)
            }
        }
        .animation(
            DSMotion.collapse.animation(reduceMotion: reduceMotion),
            value: isOpen
        )
    }
}

private struct DiffSidebarDirectoryRow: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let directory: DiffTreeDirectory
    let model: DiffModel

    private var isOpen: Bool {
        model.isDirectoryOpen(directory.path)
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
                    .foregroundStyle(palette.textTertiary.color)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .animation(
                        DSMotion.collapse.animation(reduceMotion: reduceMotion),
                        value: isOpen
                    )
                DiffFolderIcon()
                    .foregroundStyle(palette.textSecondary.color)
                Text(directory.name)
                    .font(DSTextStyle.body.font(fixedSize: DiffSidebarMetric.nameSize))
                    .foregroundStyle(palette.textSecondary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            // Overlay so idle rows keep the name's full width — the viewed control never
            // joins the HStack; it only paints over the trailing edge while hovering.
            DiffSidebarFolderViewedButton(state: viewedState) {
                model.toggleViewed(in: directory)
            }
            .dsPadding(.trailing, .s4)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .onHover { isHovering = $0 }
        .accessibilityLabel(isOpen ? "Collapse \(directory.name)" : "Expand \(directory.name)")
        .accessibilityValue(viewedAccessibilityValue)
    }

    private var rowSurface: DSColorValue {
        if isHovering { return palette.surface3 }
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
private struct DiffSidebarFolderViewedButton: View {
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

private struct DiffSidebarAggregateCheckbox: View {
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

private struct DiffSidebarFileRow: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let file: DiffFile
    let depth: Int
    let model: DiffModel

    private var isFocused: Bool { model.isFocusedInSidebar(file) }
    private var isDimmed: Bool { model.isDimmedInSidebar(file) }

    var body: some View {
        Button {
            model.revealFileInReader(file)
        } label: {
            DSHStack(spacing: .s8) {
                DiffDocumentStatusIcon(status: file.status)
                    .foregroundStyle(statusColor.color)
                Text(file.name)
                    .font(DSTextStyle.body.font(fixedSize: DiffSidebarMetric.nameSize))
                    .foregroundStyle(palette.textPrimary.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                counters
            }
            // Opacity on the glyphs only — the surface2 fill below stays solid so the
            // row still reads as marked, not washed out.
            .opacity(isDimmed ? DSOpacity.read : 1)
            .padding(.leading, DiffSidebarMetric.rowLeadingInset(depth: depth))
            .dsPadding(.trailing, .s8)
            .frame(height: DiffSidebarMetric.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(rowSurface, radius: .sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(file.status.title)")
        .accessibilityHint(
            file.hunks.isEmpty
                ? "No patch content in the reader"
                : "Scroll to this file in the reader"
        )
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityValue(isDimmed ? "Viewed" : "Not viewed")
    }

    private var rowSurface: DSColorValue {
        if isHovering { return palette.surface3 }
        if isFocused || isDimmed { return palette.surface2 }
        return palette.surface1
    }

    private var statusColor: DSColorValue {
        switch file.status {
        case .added: palette.diffAdd
        case .deleted: palette.diffDel
        case .modified, .renamed: palette.textSecondary
        }
    }

    private var counters: some View {
        DSHStack(spacing: .s4) {
            Text(file.additionsLabel)
                .foregroundStyle(palette.diffAdd.color)
                .frame(minWidth: DiffSidebarMetric.counterMinWidth, alignment: .trailing)
            Text(file.deletionsLabel)
                .foregroundStyle(palette.diffDel.color)
                .frame(minWidth: DiffSidebarMetric.counterMinWidth, alignment: .trailing)
        }
        .font(DSTextStyle.code.font(fixedSize: DiffSidebarMetric.counterSize))
        .lineLimit(1)
    }
}

// MARK: - Previews

#Preview("Sidebar — dark") {
    DiffSidebar(model: DiffModel())
        .frame(width: DiffLayout.sidebarWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.dark)
}

#Preview("Sidebar — light") {
    DiffSidebar(model: DiffModel())
        .frame(width: DiffLayout.sidebarWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.light)
}
