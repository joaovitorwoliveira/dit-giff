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
    /// One cache for the whole reader column; survives selection / read-state churn
    /// without re-lexing visible hunks on every `DiffCodeGrid` struct recreation.
    @State private var hunkRenderCache = DiffHunkRenderCache()

    var body: some View {
        // Vertical only: long lines wrap inside the viewport. With no horizontal axis,
        // `maxWidth: .infinity` resolves against the reader column again — cards, headers
        // and line fills share one width.
        //
        // Sidebar / keyboard jumps use ScrollViewReader → scrollTo(id, headerTop).
        // The id sits on a zero-height sentinel at the start of the section *body*,
        // not on the sticky header: scrolling a pinned header to the top leaves the
        // previous file's pin covering the target, so the reader appears to land on
        // the file above. Body-first lets this section's header pin cleanly on top.
        ScrollViewReader { scrollProxy in
            // Focus stays on the ScrollView so arrows / n / v fire here. Native space
            // paging does not: `.focusable()` installs a KeyViewProxy first responder,
            // so in-file keys are applied through scrollPosition instead.
            ScrollView {
                // Stack spacing is 0 on purpose: with pinned section headers the
                // header and body are separate LazyVStack children, so any gap
                // here would open the card between them. Inter-file breathing
                // lives as bottom padding on the section body instead — still
                // outside the sticky header, so scrollTo's body sentinel stays
                // flush under the pin.
                LazyVStack(
                    alignment: .leading,
                    spacing: 0,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(model.sectionFiles) { file in
                        Section {
                            // Always present — even when the body is collapsed — so a
                            // jump to a viewed/collapsed file still has an anchor.
                            Color.clear
                                .frame(height: 0)
                                .id(
                                    DiffFileNavigationResolver.scrollAnchorID(
                                        filePath: file.path
                                    )
                                )
                                .accessibilityHidden(true)
                            DiffFileBody(
                                file: file,
                                model: model,
                                isSelectingLines: $isSelectingLines
                            )
                            // Card-to-card gap (and collapsed-header-to-next-card).
                            // Stays on the body so a collapsed file still breathes
                            // and the last file keeps room before the list pad.
                            .dsPadding(.bottom, .s16)
                        } header: {
                            DiffFileStickyHeader(file: file, model: model)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.horizontal, .s24)
                .dsPadding(.top, .s16)
                // Viewport-tall trailing slack so a near-end file can still land with
                // its header at the top — a fixed s48 left the last cards mid-screen.
                .padding(
                    .bottom,
                    DiffReaderFileJumpLayout.bottomScrollSlack(
                        viewportHeight: scrollViewportHeight,
                        minimumPadding: DSSpace.s48.points
                    )
                )
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
                // Proxy file jumps do not write ScrollPosition; mirror geometry so the
                // binding cannot yank the reader back to a stale offset mid-sequence.
                if model.readerScrollRequest != nil {
                    scrollPosition.scrollTo(y: visible.offsetY)
                }
            }
            .focusable()
            .focused(isFocused)
            .focusEffectDisabled()
            // `.repeat` is required for hold-to-scroll and hold-to-scan files (←/→).
            // Folder jumps / n / v still refuse repeat inside `handleKeyPress`.
            // ←/→ walk visible tree lines (file or folder); key-repeat is intentional.
            .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
            .onChange(of: model.readerScrollRequest) { _, request in
                guard let request else { return }
                performReaderScroll(request, scrollProxy: scrollProxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface0)
        .environment(\.diffHunkRenderCache, hunkRenderCache)
        .onChange(of: model.loadGeneration) { _, _ in
            hunkRenderCache.reset()
        }
        // A tap that is not eaten by a control or a drag clears the selection and
        // claims keyboard focus so arrows / n / v work without a second gesture.
        .onTapGesture {
            isFocused.wrappedValue = true
            guard !isSelectingLines else { return }
            model.clearSelection()
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // No modifiers.isEmpty gate here — Shift+↑/↓ are folder jumps. The pipeline
        // is the only accept/reject policy; tests drive it without mounting SwiftUI.
        let isRepeat = keyPress.phase.contains(.repeat)
        guard let intent = DiffReaderKeyPressPipeline.intent(
            for: readerKeyEvent(from: keyPress),
            isRepeat: isRepeat
        ) else { return .ignored }
        DiffReaderKeyIntentDispatch.perform(
            intent,
            actions: DiffReaderKeyIntentDispatch.Actions(
                goToNextFile: { model.goToNextFile(isKeyRepeat: isRepeat) },
                goToPreviousFile: { model.goToPreviousFile(isKeyRepeat: isRepeat) },
                goToNextFolder: { model.goToNextFolder() },
                goToPreviousFolder: { model.goToPreviousFolder() },
                openFocusedFolder: { model.openFocusedFolder() },
                closeFocusedFolder: { model.closeFocusedFolder() },
                goToNextUnreadFile: { model.goToNextUnreadFile() },
                toggleViewed: { model.toggleViewedOnFocusedFile() },
                scroll: { applyReaderScroll($0, isRepeat: isRepeat) }
            )
        )
        return .handled
    }

    /// Bridges SwiftUI's `KeyPress` into the pure domain event the mapping tests cover.
    private func readerKeyEvent(from keyPress: KeyPress) -> DiffReaderKeyEvent {
        let key: DiffReaderKeyEvent.Key
        switch keyPress.key {
        case .leftArrow: key = .leftArrow
        case .rightArrow: key = .rightArrow
        case .upArrow: key = .upArrow
        case .downArrow: key = .downArrow
        case .space: key = .space
        case .pageUp: key = .pageUp
        case .pageDown: key = .pageDown
        default: key = .character(keyPress.characters)
        }
        return DiffReaderKeyEvent(
            key: key,
            modifiers: DiffReaderKeyModifiers(
                shift: keyPress.modifiers.contains(.shift),
                command: keyPress.modifiers.contains(.command),
                option: keyPress.modifiers.contains(.option),
                control: keyPress.modifiers.contains(.control)
            )
        )
    }

    private func applyReaderScroll(_ intent: DiffReaderScrollIntent, isRepeat: Bool) {
        let target = DiffReaderScrollPaging.targetOffset(
            currentOffset: scrollOffsetY,
            viewportHeight: scrollViewportHeight,
            lineHeight: DiffViewerMetric.codeLineHeight,
            intent: intent,
            isRepeat: isRepeat
        )
        scrollPosition.scrollTo(y: target)
    }

    private func performReaderScroll(
        _ request: DiffReaderScrollRequest,
        scrollProxy: ScrollViewProxy
    ) {
        let anchorID = DiffFileNavigationResolver.scrollAnchorID(filePath: request.path)
        let anchor = fileJumpUnitPoint
        if DiffReaderScrollRetry.isAnimated(attempt: request.attempt) {
            withAnimation(DSMotion.jump.animation(reduceMotion: reduceMotion)) {
                scrollProxy.scrollTo(anchorID, anchor: anchor)
            }
        } else {
            // Correctives must not inherit the jump animation — that inheritance is the
            // late mid-screen flick after layout settles.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollProxy.scrollTo(anchorID, anchor: anchor)
            }
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

    /// Maps the pure file-jump policy onto SwiftUI. Only `.headerTop` exists on purpose.
    private var fileJumpUnitPoint: UnitPoint {
        switch DiffFileNavigationResolver.fileJumpAnchor {
        case .headerTop:
            return .top
        }
    }
}

// MARK: - Keyboard

/// Snapshot of the reader's scroll geometry for `onScrollGeometryChange`.
private struct DiffReaderVisibleScroll: Equatable {
    var offsetY: CGFloat
    var viewportHeight: CGFloat
}

// MARK: - File card chrome

/// Sticky section headers leave the LazyVStack flow, so one outer rounded rect cannot
/// wrap header + body. Each piece paints matching partial corners; the body's top
/// stroke overlaps the header's bottom edge by one hairline so the join is a single line.
enum DiffFileCardChrome {
    static func shape(topRounded: Bool, bottomRounded: Bool) -> UnevenRoundedRectangle {
        let top = topRounded ? DSRadius.md.points : 0
        let bottom = bottomRounded ? DSRadius.md.points : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .continuous
        )
    }
}

extension View {
    /// Bottom half of the per-file card. Top border tucks under the sticky header's
    /// bottom stroke so the seam is one hairline, not two.
    ///
    /// No `clipShape` here: selection popovers sit above the first hunk and must be
    /// free to paint past the card's top edge. Bottom-corner clipping of edge-to-edge
    /// line fills lives on the last hunk's content instead (see DiffHunkBlock).
    func diffFileCardBodyChrome(palette: DSPalette) -> some View {
        let shape = DiffFileCardChrome.shape(topRounded: false, bottomRounded: true)
        return self
            .background { shape.fill(palette.surface1.color) }
            .overlay {
                shape.strokeBorder(
                    palette.borderSubtle.color,
                    lineWidth: DiffViewerMetric.hairline
                )
            }
            .padding(.top, -DiffViewerMetric.hairline)
    }
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

    // Sparkles hit 31pt (6+19+6); Viewed chip 29pt (6+17+6). Band centers the taller
    // control with 2.5pt slack; 48pt file header stays visually dominant.
    static let hunkHeaderHeight: CGFloat = 36
    static let hunkHeaderSize: CGFloat = 11

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
