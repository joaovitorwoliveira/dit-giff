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
                DiffSidebarFileRow(file: file, depth: depth)
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
            DiffSidebarDirectoryRow(
                directory: directory,
                isOpen: isOpen,
                toggle: { model.toggleDirectory(directory.path) }
            )
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
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
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
            .padding(.leading, DiffSidebarMetric.rowLeadingInset(depth: directory.depth))
            .dsPadding(.trailing, .s8)
            .frame(height: DiffSidebarMetric.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(isHovering ? palette.surface3 : palette.surface1, radius: .sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isOpen ? "Collapse \(directory.name)" : "Expand \(directory.name)")
    }
}

private struct DiffSidebarFileRow: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let file: DiffFile
    let depth: Int

    var body: some View {
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
        .padding(.leading, DiffSidebarMetric.rowLeadingInset(depth: depth))
        .dsPadding(.trailing, .s8)
        .frame(height: DiffSidebarMetric.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface(isHovering ? palette.surface3 : palette.surface1, radius: .sm)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.name), \(file.status.title)")
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
