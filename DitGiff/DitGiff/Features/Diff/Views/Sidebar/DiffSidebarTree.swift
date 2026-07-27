import SwiftUI

// MARK: - Tree

struct DiffSidebarTree: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: DiffModel
    var onFileRevealed: () -> Void = {}

    /// True while the user is driving the sidebar scroll (drag / wheel coast).
    /// Programmatic `.animating` must not set this — otherwise follow-scroll would
    /// refuse its own next step.
    @State private var isUserScrolling = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                DSVStack(alignment: .leading, spacing: nil) {
                    if model.fileTree.isEmpty {
                        emptyState
                    } else {
                        DiffSidebarTreeNodes(
                            nodes: model.fileTree,
                            model: model,
                            onFileRevealed: onFileRevealed
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.horizontal, .s8)
                .dsPadding(.top, .s8)
                .dsPadding(.bottom, .s24)
            }
            .onScrollPhaseChange { _, newPhase in
                isUserScrolling = newPhase == .tracking
                    || newPhase == .interacting
                    || newPhase == .decelerating
            }
            .onChange(of: model.focusedFilePath) { _, newPath in
                scrollFocusedLineIntoView(proxy: proxy, path: newPath)
            }
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

    /// Minimum scroll (`anchor: nil`) so an off-screen focused row enters the viewport
    /// without jumping when it is already visible. Never focuses the row — keyboard
    /// focus stays on the reader. Never opens closed folders: ←/→ skip hidden rows, so
    /// the cursor path is already visible when this runs.
    private func scrollFocusedLineIntoView(proxy: ScrollViewProxy, path: String?) {
        guard let path, !isUserScrolling else { return }
        animateScrollToFocusedLine(proxy: proxy, path: path)
    }

    private func animateScrollToFocusedLine(proxy: ScrollViewProxy, path: String) {
        withAnimation(DSMotion.read.animation(reduceMotion: reduceMotion)) {
            proxy.scrollTo(path, anchor: nil)
        }
    }
}

struct DiffSidebarTreeNodes: View {
    let nodes: [DiffTreeNode]
    let model: DiffModel
    let onFileRevealed: () -> Void

    var body: some View {
        ForEach(nodes) { node in
            switch node {
            case let .directory(directory):
                DiffSidebarDirectoryBranch(
                    directory: directory,
                    model: model,
                    onFileRevealed: onFileRevealed
                )
            case let .file(file, depth):
                DiffSidebarFileRow(
                    file: file,
                    depth: depth,
                    model: model,
                    onFileRevealed: onFileRevealed
                )
            }
        }
    }
}

struct DiffSidebarDirectoryBranch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let directory: DiffTreeDirectory
    let model: DiffModel
    let onFileRevealed: () -> Void

    private var isOpen: Bool {
        model.isDirectoryOpen(directory.path)
    }

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            DiffSidebarDirectoryRow(directory: directory, model: model)
            if isOpen {
                DiffSidebarTreeNodes(
                    nodes: directory.children,
                    model: model,
                    onFileRevealed: onFileRevealed
                )
            }
        }
        .animation(
            DSMotion.collapse.animation(reduceMotion: reduceMotion),
            value: isOpen
        )
    }
}
