import SwiftUI

/// The change map: how far the reader has got, which files belong to the diff, and a
/// filter that keeps the tree honest about what still matches.
struct DiffSidebar: View {
    @Environment(\.dsPalette) private var palette

    @Bindable var model: DiffModel
    /// Called after a file row click so the shell can hand keyboard focus to the reader.
    var onFileRevealed: () -> Void = {}

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            DiffSidebarHeader(model: model)
            DiffSidebarFilter(model: model)
            DiffSidebarTree(model: model, onFileRevealed: onFileRevealed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dsSurface(palette.surface1)
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
enum DiffSidebarMetric {
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
