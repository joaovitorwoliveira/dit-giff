import SwiftUI

/// The widths the three regions are worth. The window's minimum is derived from these,
/// so the diff can never open into a window that cannot hold it.
enum DiffLayout {
    /// Default preferred width; also the window-minimum budget for the change map.
    static let sidebarWidth: CGFloat = 280
    /// Floor so nested paths still leave room after depth-3 indent, chevron, and counters.
    static let minimumSidebarWidth: CGFloat = 200
    /// Cap at the viewer's own floor so the change map cannot outgrow the reader.
    static let maximumSidebarWidth: CGFloat = 480
    /// Hit width of the resize divider between the change map and the reader.
    /// Must match the divider's layout width — it is subtracted when sizing the reader.
    static let sidebarDividerWidth: CGFloat = 12
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

    /// Survives relaunch via `UserDefaults`. Kept here — not on `DiffModel` — so a
    /// workspace preference cannot collide with the model rewrite in flight.
    @AppStorage(DiffSidebarWidth.storageKey) private var storedSidebarWidth =
        DiffSidebarWidth.defaultStorageValue

    /// In-gesture ghost position only. `nil` when idle. Never drives sidebar or reader layout.
    @State private var previewSidebarWidth: CGFloat?

    var body: some View {
        DSVStack(spacing: nil) {
            DiffTopBar(model: model, back: back, toggleTheme: toggleTheme)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface0)
    }

    /// Width the change map is laid out at. Comes only from storage — not from the drag preview.
    private var appliedSidebarWidth: CGFloat {
        DiffSidebarWidth.clamped(CGFloat(storedSidebarWidth))
    }

    private func commitSidebarWidth(_ width: CGFloat) {
        storedSidebarWidth = Double(DiffSidebarWidth.clamped(width))
        previewSidebarWidth = nil
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
        // Reader width is the leftover HStack slot (`maxWidth: .infinity`). During a
        // resize drag, appliedSidebarWidth is frozen — only `previewSidebarWidth`
        // moves a ghost line — so the LazyVStack of code is not invalidated per pixel.
        ZStack(alignment: .topLeading) {
            DSHStack(alignment: .top, spacing: nil) {
                sidebar
                if model.isSidebarOpen {
                    DiffSidebarResizeDivider(
                        committedWidth: appliedSidebarWidth,
                        previewWidth: $previewSidebarWidth,
                        onCommit: commitSidebarWidth
                    )
                }
                DiffViewer(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.isChatOpen {
                    DiffChatPanel(model: model)
                        .frame(width: DiffLayout.chatWidth, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if model.isSidebarOpen, let preview = previewSidebarWidth {
                resizeGhost(at: preview)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            DSMotion.collapse.animation(reduceMotion: reduceMotion),
            value: model.isChatOpen
        )
    }

    /// Hairline that follows the pointer during drag. No reader content, no sidebar reflow.
    private func resizeGhost(at previewWidth: CGFloat) -> some View {
        Rectangle()
            .fill(palette.textTertiary.color)
            .frame(width: DiffViewMetric.resizeGhostWidth)
            .frame(maxHeight: .infinity)
            .offset(x: previewWidth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Closed is zero width, not hidden: the region keeps its place in the row so the
    /// diff slides over instead of jumping. Preferred width is untouched while closed,
    /// so reopening restores the reader's last drag.
    private var sidebar: some View {
        DiffSidebar(model: model)
            .frame(width: model.isSidebarOpen ? appliedSidebarWidth : 0, alignment: .top)
            .clipped()
            .animation(
                DSMotion.collapse.animation(reduceMotion: reduceMotion),
                value: model.isSidebarOpen
            )
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
    static let statusMaxWidth: CGFloat = 420
    static let resizeGhostWidth: CGFloat = 1
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
