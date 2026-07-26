import SwiftUI

/// The center column: each file in `sectionFiles` (text with hunks, or a short
/// binary / submodule / no-content entry), sticky headers, and the body itself.
/// A drag across lines opens the selection popover; a tap elsewhere clears it.
struct DiffViewer: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: DiffModel
    /// Owned by the diff shell so a sidebar file click can hand keyboard focus here
    /// without an extra click on the reader.
    var isFocused: FocusState<Bool>.Binding
    /// Set while a drag is choosing lines, so the viewer's "tap outside" clear does not
    /// erase the selection the drag just made.
    @State private var isSelectingLines = false
    /// Point-mode scroll position for in-file keyboard paging. File jumps still use
    /// ScrollViewReader; geometry below is the source of truth for the current offset
    /// because a reader jump does not update `scrollPosition.y`.
    @State private var scrollPosition = ScrollPosition(y: 0)
    @State private var scrollOffsetY: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0

    var body: some View {
        // Vertical only: long lines wrap inside the viewport. With no horizontal axis,
        // `maxWidth: .infinity` resolves against the reader column again — cards, headers
        // and line fills share one width.
        //
        // Sidebar jumps use ScrollViewReader → scrollTo(headerID, anchor: .top).
        // The id lives on the sticky header (one per section file). LazyVStack can
        // resolve that id without materialising every code line between here and there.
        ScrollViewReader { scrollProxy in
            // Focus stays on the ScrollView so j / k / n / v fire here. Native space
            // paging does not: `.focusable()` installs a KeyViewProxy first responder,
            // so in-file keys are applied through scrollPosition instead.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.sectionFiles) { file in
                        Section {
                            DiffFileBody(
                                file: file,
                                model: model,
                                isSelectingLines: $isSelectingLines
                            )
                        } header: {
                            DiffFileStickyHeader(file: file, model: model)
                                .dsPadding(.top, .s16)
                                .id(
                                    DiffFileNavigationResolver.scrollAnchorID(
                                        filePath: file.path
                                    )
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.horizontal, .s24)
                .dsPadding(.bottom, .s48)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: DiffReaderVisibleScroll.self) { geometry in
                DiffReaderVisibleScroll(
                    offsetY: geometry.contentOffset.y,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, visible in
                scrollOffsetY = visible.offsetY
                scrollViewportHeight = visible.viewportHeight
            }
            .focusable()
            .focused(isFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: .down, action: handleKeyPress)
            .onChange(of: model.readerScrollRequest) { _, request in
                guard let request else { return }
                performReaderScroll(request, scrollProxy: scrollProxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface0)
        // A tap that is not eaten by a control or a drag clears the selection and
        // claims keyboard focus so j / k / n / v work without a second gesture.
        .onTapGesture {
            isFocused.wrappedValue = true
            guard !isSelectingLines else { return }
            model.clearSelection()
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if let intent = readerScrollIntent(for: keyPress) {
            applyReaderScroll(intent)
            return .handled
        }
        // Letter shortcuts only fire while this column is focused. The sidebar filter
        // and chat composer keep their own FocusState, so typing "join" there never
        // reaches these handlers.
        guard keyPress.modifiers.isEmpty else { return .ignored }
        switch keyPress.characters {
        case DiffReaderKey.nextFile:
            model.goToNextFile()
            return .handled
        case DiffReaderKey.previousFile:
            model.goToPreviousFile()
            return .handled
        case DiffReaderKey.nextUnreadFile:
            model.goToNextUnreadFile()
            return .handled
        case DiffReaderKey.toggleViewed:
            model.toggleViewedOnFocusedFile()
            return .handled
        default:
            return .ignored
        }
    }

    private func readerScrollIntent(for keyPress: KeyPress) -> DiffReaderScrollIntent? {
        let kind: DiffReaderScrollKeyEvent.Kind
        switch keyPress.key {
        case .space:
            kind = .space
        case .pageDown:
            kind = .pageDown
        case .pageUp:
            kind = .pageUp
        case .downArrow:
            kind = .downArrow
        case .upArrow:
            kind = .upArrow
        default:
            return nil
        }
        // Cmd/option/control must not become paging — leave those to the system.
        let nonShift = keyPress.modifiers.subtracting(.shift)
        guard nonShift.isEmpty else { return nil }
        return DiffReaderScrollKeyMapping.intent(
            for: DiffReaderScrollKeyEvent(
                kind: kind,
                shift: keyPress.modifiers.contains(.shift)
            )
        )
    }

    private func applyReaderScroll(_ intent: DiffReaderScrollIntent) {
        let target = DiffReaderScrollPaging.targetOffset(
            currentOffset: scrollOffsetY,
            viewportHeight: scrollViewportHeight,
            lineHeight: DiffViewerMetric.codeLineHeight,
            intent: intent
        )
        scrollPosition.scrollTo(y: target)
    }

    private func performReaderScroll(
        _ request: DiffReaderScrollRequest,
        scrollProxy: ScrollViewProxy
    ) {
        let anchorID = DiffFileNavigationResolver.scrollAnchorID(filePath: request.path)
        if DiffReaderScrollRetry.isAnimated(attempt: request.attempt) {
            withAnimation(DSMotion.jump.animation(reduceMotion: reduceMotion)) {
                scrollProxy.scrollTo(anchorID, anchor: .top)
            }
        } else {
            scrollProxy.scrollTo(anchorID, anchor: .top)
        }

        guard let delay = DiffReaderScrollRetry.delayAfter(attempt: request.attempt) else {
            model.clearReaderScrollRequest()
            return
        }

        let nonce = request.nonce
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard model.readerScrollRequest?.nonce == nonce else { return }
            model.advanceReaderScrollRequest()
        }
    }
}

// MARK: - Keyboard

/// Single-letter reader shortcuts. Named so the handler never compares magic strings.
private enum DiffReaderKey {
    static let nextFile = "j"
    static let previousFile = "k"
    static let nextUnreadFile = "n"
    static let toggleViewed = "v"
}

/// Snapshot of the reader's scroll geometry for `onScrollGeometryChange`.
private struct DiffReaderVisibleScroll: Equatable {
    var offsetY: CGFloat
    var viewportHeight: CGFloat
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
enum DiffViewerMetric {
    static let hairline: CGFloat = 1

    static let headerHeight: CGFloat = 48
    static let chevronHitSize: CGFloat = 16
    static let directorySize: CGFloat = 12.5
    static let fileNameSize: CGFloat = 14
    static let statsSize: CGFloat = 11
    static let iconButtonPadding: CGFloat = 6
    static let viewedVerticalPadding: CGFloat = 6
    static let viewedCheckboxGap: CGFloat = 6
    static let viewedLabelSize: CGFloat = 13

    static let hunkHeaderHeight: CGFloat = 28
    static let hunkHeaderSize: CGFloat = 11
    static let hunkActionPadding: CGFloat = 3

    /// The analysis-note clue on the hunk's leading edge — same rail the v1 prototype used.
    static let noteMarkerWidth: CGFloat = 3
    static let noteMarkerHeight: CGFloat = 16
    static let noteMarkerTop: CGFloat = 6
    static let noteMarkerRadius: CGFloat = 2

    static let oldLineNumberWidth: CGFloat = 36
    static let newLineNumberWidth: CGFloat = 28
    static let signWidth: CGFloat = 16
    static let codeSize: CGFloat = 13
    /// Single-line row height — also the fallback for selection hit-testing before a
    /// wrapped row has reported its measured height.
    static let codeLineHeight: CGFloat = 20.15

    /// The `dg-sel-line` mark: a leading rule on every selected row.
    static let selectionBarWidth: CGFloat = 3

    /// Dimmed chrome for AI actions that have nothing to say yet (Slice 4).
    static let disabledOpacity: Double = 0.35

    /// SF Symbol point size inside the explain control — sits in the same 19pt frame
    /// the hand-drawn icon used.
    static let explainSparklesSize: CGFloat = 13
}

// MARK: - Previews

#Preview("Viewer — dark") {
    DiffViewerPreviewHost()
        .frame(width: DiffLayout.minimumViewerWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.dark)
}

#Preview("Viewer — light") {
    DiffViewerPreviewHost()
        .frame(width: DiffLayout.minimumViewerWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.light)
}

private struct DiffViewerPreviewHost: View {
    @FocusState private var isReaderFocused: Bool

    var body: some View {
        DiffViewer(model: DiffModel(), isFocused: $isReaderFocused)
    }
}
