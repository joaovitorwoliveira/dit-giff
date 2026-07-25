import SwiftUI

/// The bar over the diff: the change map's switch, the mark, the pair of branches that is
/// also the way out, what the diff weighs, and the theme. The window's own title bar
/// supplies the traffic lights, so the bar does not draw its own.
struct DiffTopBar: View {
    @Environment(\.dsPalette) private var palette

    let model: DiffModel
    let back: () -> Void
    let toggleTheme: (ColorScheme) -> Void

    var body: some View {
        DSHStack(spacing: .s16) {
            DiffSidebarToggleButton(isOpen: model.isSidebarOpen) { model.toggleSidebar() }
            DiffLogoIcon()
                .foregroundStyle(palette.textPrimary.color)
            DiffBranchPill(
                compareBranch: model.compareBranch,
                baseBranch: model.baseBranch,
                back: back
            )
            .frame(maxWidth: .infinity)
            DSHStack(spacing: .s12) {
                DiffChangeCounters(model: model)
                DiffThemeToggleButton(toggle: toggleTheme)
            }
        }
        .dsPadding(.horizontal, .s16)
        .frame(height: DiffTopBarMetric.height)
        .dsSurface(palette.surface1)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(height: DiffTopBarMetric.hairline)
        }
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
private enum DiffTopBarMetric {
    static let height: CGFloat = 52
    static let hairline: CGFloat = 1

    /// The prototype applies a type token and then overrides only its size inline.
    static let statsSize: CGFloat = 11

    static let iconButtonPadding: CGFloat = 4
    static let themeButtonPadding: CGFloat = 5
    static let pillVerticalPadding: CGFloat = 4
    static let pillDividerTrailingGap: CGFloat = 2
}

// MARK: - Buttons

private struct DiffSidebarToggleButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            DiffSidebarToggleIcon()
                .foregroundStyle(
                    isHovering ? palette.textPrimary.color : palette.textTertiary.color
                )
                .padding(DiffTopBarMetric.iconButtonPadding)
                .dsSurface(isHovering ? palette.surface3 : palette.surface1, radius: .sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusable(radius: .sm)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isOpen ? "Hide change map" : "Show change map")
    }
}

/// The pair of branches, and the way back to the setup that chose them.
private struct DiffBranchPill: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let compareBranch: String
    let baseBranch: String
    let back: () -> Void

    var body: some View {
        Button(action: back) {
            DSHStack(spacing: .s8) {
                backArrow
                Text(compareBranch)
                    .foregroundStyle(palette.textPrimary.color)
                Text("→")
                    .foregroundStyle(palette.textTertiary.color)
                Text(baseBranch)
                    .foregroundStyle(palette.textPrimary.color)
            }
            .dsText(.code)
            .lineLimit(1)
            .padding(.vertical, DiffTopBarMetric.pillVerticalPadding)
            .dsPadding(.leading, .s8)
            .dsPadding(.trailing, .s12)
            .dsSurface(isHovering ? palette.surface2 : palette.surface3, radius: .sm)
            .dsBorder(isHovering ? palette.diffAdd : palette.border, radius: .sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusable(radius: .sm)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Back — switch branch or repository")
    }

    /// The arrow is fenced off from the branches by a rule: it is a different action
    /// from reading the pair.
    private var backArrow: some View {
        Image(systemName: "arrow.left")
            .font(.system(size: DiffIconMetric.backArrowSize))
            .foregroundStyle(palette.textSecondary.color)
            .padding(.trailing, DiffTopBarMetric.pillDividerTrailingGap)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(palette.border.color)
                    .frame(width: DiffTopBarMetric.hairline)
            }
            .dsPadding(.trailing, .s4)
    }
}

private struct DiffChangeCounters: View {
    @Environment(\.dsPalette) private var palette

    let model: DiffModel

    var body: some View {
        DSHStack(spacing: .s12) {
            Text(model.fileCountText)
                .dsText(.label)
                .foregroundStyle(palette.textSecondary.color)
            stats
                .font(DSTextStyle.code.font(fixedSize: DiffTopBarMetric.statsSize))
                .lineLimit(1)
        }
    }

    /// One `Text` so the space between the two counts is the same space the prototype
    /// puts there, rather than a stack's gap.
    private var stats: Text {
        let additions = Text(model.additionsText).foregroundStyle(palette.diffAdd.color)
        let deletions = Text(model.deletionsText).foregroundStyle(palette.diffDel.color)
        return Text("\(additions) \(deletions)")
    }
}

private struct DiffThemeToggleButton: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let toggle: (ColorScheme) -> Void

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button {
            toggle(colorScheme)
        } label: {
            // The button shows where you are, and clicking takes you to the other side.
            Image(systemName: isDark ? "moon" : "sun.max")
                .font(.system(size: DiffIconMetric.themeSize))
                .foregroundStyle(
                    isHovering ? palette.textPrimary.color : palette.textSecondary.color
                )
                .padding(DiffTopBarMetric.themeButtonPadding)
                .dsSurface(isHovering ? palette.surface3 : palette.surface1, radius: .sm)
                .dsBorder(palette.border, radius: .sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dsFocusable(radius: .sm)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isDark ? "Light mode" : "Dark mode")
    }
}

// MARK: - Previews

#Preview("Top bar — dark") {
    DiffTopBar(model: DiffModel(), back: {}, toggleTheme: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Top bar — light") {
    DiffTopBar(model: DiffModel(), back: {}, toggleTheme: { _ in })
        .preferredColorScheme(.light)
}
