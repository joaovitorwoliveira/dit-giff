import SwiftUI

/// The widths the three regions are worth. The window's minimum is derived from these,
/// so the diff can never open into a window that cannot hold it.
enum DiffLayout {
    static let sidebarWidth: CGFloat = 280
    static let chatWidth: CGFloat = 340
    /// Enough for the four-column grid and a line of code beside it.
    static let minimumViewerWidth: CGFloat = 480

    static var minimumWidth: CGFloat { sidebarWidth + minimumViewerWidth + chatWidth }
    static let minimumHeight: CGFloat = 640
}

/// The diff screen's shell: the bar on top, and under it the change map, the diff, and
/// the conversation — or a loading / failure stand-in while the patch is fetched.
struct DiffView: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var model: DiffModel
    let back: () -> Void
    let toggleTheme: (ColorScheme) -> Void

    var body: some View {
        DSVStack(spacing: nil) {
            DiffTopBar(model: model, back: back, toggleTheme: toggleTheme)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface0)
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            DiffLoadStatusView(
                title: "Loading diff…",
                detail: "Reading the patch for \(model.compareBranch) → \(model.baseBranch)."
            )
        case let .failed(message):
            DiffLoadStatusView(
                title: "Could not load this diff",
                detail: message,
                isError: true
            )
        case .loaded:
            regions
        }
    }

    private var regions: some View {
        DSHStack(alignment: .top, spacing: nil) {
            sidebar
            DiffViewer(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.isChatOpen {
                DiffChatPanel(model: model)
                    .frame(width: DiffLayout.chatWidth, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            DSMotion.collapse.animation(reduceMotion: reduceMotion),
            value: model.isChatOpen
        )
    }

    /// Closed is zero width, not hidden: the region keeps its place in the row so the
    /// diff slides over instead of jumping.
    private var sidebar: some View {
        DiffSidebar(model: model)
            .frame(width: model.isSidebarOpen ? DiffLayout.sidebarWidth : 0, alignment: .top)
            .overlay(alignment: .trailing) {
                if model.isSidebarOpen {
                    edge
                }
            }
            .clipped()
            .animation(
                DSMotion.collapse.animation(reduceMotion: reduceMotion),
                value: model.isSidebarOpen
            )
    }

    private var edge: some View {
        Rectangle()
            .fill(palette.borderSubtle.color)
            .frame(width: DiffViewMetric.hairline)
    }
}

// MARK: - Load status

private struct DiffLoadStatusView: View {
    @Environment(\.dsPalette) private var palette

    let title: String
    let detail: String
    var isError: Bool = false

    var body: some View {
        DSVStack(alignment: .center, spacing: .s12) {
            Text(title)
                .dsText(.panelTitle)
                .foregroundStyle(isError ? palette.textError.color : palette.textPrimary.color)
                .multilineTextAlignment(.center)
            Text(detail)
                .dsText(.body)
                .foregroundStyle(palette.textSecondary.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: DiffViewMetric.statusMaxWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsPadding(.all, .s24)
        .dsSurface(palette.surface0)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
private enum DiffViewMetric {
    static let hairline: CGFloat = 1
    static let statusMaxWidth: CGFloat = 420
}

// MARK: - Previews

#Preview("Diff shell — dark") {
    DiffView(model: DiffModel(), back: {}, toggleTheme: { _ in })
        .frame(width: DiffLayout.minimumWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.dark)
}

#Preview("Diff shell — light") {
    DiffView(model: DiffModel(), back: {}, toggleTheme: { _ in })
        .frame(width: DiffLayout.minimumWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.light)
}
