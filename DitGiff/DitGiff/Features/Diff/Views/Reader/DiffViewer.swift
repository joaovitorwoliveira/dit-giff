import SwiftUI

/// The center column: each file in `sectionFiles` (text with hunks, or a short
/// binary / submodule / no-content entry), sticky headers, and the body itself.
/// A drag across lines opens the selection popover; a tap elsewhere clears it.
struct DiffViewer: View {
    @Environment(\.dsPalette) private var palette

    let model: DiffModel
    /// Owned by the diff shell so a sidebar file click can hand keyboard focus here
    /// without an extra click on the reader.
    var isFocused: FocusState<Bool>.Binding
    /// Set while a drag is choosing lines, so the viewer's "tap outside" clear does not
    /// erase the selection the drag just made.
    @State private var isSelectingLines = false
    /// Point-mode scroll position for in-file paging and sentinel point corrections.
    @State private var scrollPosition = ScrollPosition(y: 0)
    /// ScrollView container height — measured outside scroll content so bottom slack
    /// padding does not feed back into `onScrollGeometryChange`.
    @State private var readerViewportHeight: CGFloat = 0
    /// Reference copy for paging UI and sentinel → content-offset conversion.
    @State private var scrollGeometryStore = DiffReaderScrollGeometryStore()
    /// File-jump samples and correction state — reference storage for geometry callbacks.
    @State private var fileJumpController = DiffReaderFileJumpController()
    /// One cache for the whole reader column; survives selection / read-state churn
    /// without re-lexing visible hunks on every `DiffCodeGrid` struct recreation.
    @State private var hunkRenderCache = DiffHunkRenderCache()

    var body: some View {
        // Vertical only: long lines wrap inside the viewport. With no horizontal axis,
        // `maxWidth: .infinity` resolves against the reader column again — cards, headers
        // and line fills share one width.
        //
        // Sidebar / keyboard jumps: `ScrollViewReader.scrollTo` on the body-start sentinel
        // id, then at most bounded point corrections from sentinel geometry. Focus stays on
        // the ScrollView so arrows / n / v fire here. Native space paging does not:
        // `.focusable()` installs a KeyViewProxy first responder, so in-file keys are
        // applied through scrollPosition instead.
        ScrollViewReader { scrollProxy in
            ScrollView {
                // Stack spacing is 0 on purpose: with pinned section headers the
                // header and body are separate LazyVStack children, so any gap
                // here would open the card between them. Inter-file breathing
                // lives as an unconditional clear spacer at the end of the
                // section body — still outside the sticky header.
                LazyVStack(
                    alignment: .leading,
                    spacing: 0,
                    pinnedViews: [.sectionHeaders]
                ) {
                    ForEach(model.sectionFiles) { file in
                        Section {
                            Color.clear
                                .frame(height: 0)
                                .id(
                                    DiffFileNavigationResolver.scrollAnchorID(
                                        filePath: file.path
                                    )
                                )
                                .accessibilityHidden(true)
                                .onGeometryChange(for: DiffReaderBodySentinelSample.self) { proxy in
                                    DiffReaderBodySentinelSample(
                                        viewportMinY: proxy.frame(in: .scrollView).minY,
                                        contentMinY: proxy.frame(
                                            in: .named(DiffReaderScrollContentSpace.name)
                                        ).minY
                                    )
                                } action: { sample in
                                    if fileJumpController.recordSentinelSample(
                                        path: file.path,
                                        sample: sample
                                    ) {
                                        fileJumpController.scheduleDeferredProcessing {
                                            processPendingSentinelSample()
                                        }
                                    }
                                }
                            DiffFileBody(
                                file: file,
                                model: model,
                                isSelectingLines: $isSelectingLines
                            )
                            // Always present — padding on an empty (collapsed)
                            // DiffFileBody collapses to zero height in SwiftUI.
                            Color.clear
                                .frame(height: DiffReaderFileCardGap.height)
                                .accessibilityHidden(true)
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
                        viewportHeight: readerViewportHeight,
                        minimumPadding: DSSpace.s48.points
                    )
                )
                // Modifier order is scroll math: this named space must share the ScrollView
                // content child's origin (after padding). Placing it on the inner LazyVStack
                // before top padding makes sentinel contentMinY miss the 16pt inset.
                .coordinateSpace(name: DiffReaderScrollContentSpace.name)
            }
            .scrollPosition($scrollPosition)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                guard height > 0 else { return }
                let wasUnmeasured = readerViewportHeight == 0
                if wasUnmeasured {
                    readerViewportHeight = height
                    if let request = model.readerScrollRequest,
                       request.scrollStyle == .settled
                    {
                        scheduleViewportReadyRestart(
                            request: request,
                            scrollProxy: scrollProxy
                        )
                    }
                    return
                }
                guard abs(height - readerViewportHeight) > DiffReaderScrollGeometryTolerance.viewportResizeLatch
                else { return }
                readerViewportHeight = height
            }
            .onScrollGeometryChange(for: DiffReaderVisibleScroll.self) { geometry in
                DiffReaderVisibleScroll(
                    offsetY: geometry.contentOffset.y,
                    viewportHeight: geometry.containerSize.height,
                    viewportWidth: geometry.containerSize.width,
                    contentHeight: geometry.contentSize.height
                )
            } action: { _, visible in
                scrollGeometryStore.update(
                    offsetY: visible.offsetY,
                    viewportHeight: visible.viewportHeight,
                    viewportWidth: visible.viewportWidth,
                    contentHeight: visible.contentHeight
                )
            }
            .focusable()
            .focused(isFocused)
            .focusEffectDisabled()
            // `.repeat` is required for hold-to-scroll and hold-to-scan files (←/→).
            // Folder jumps / n / v still refuse repeat inside `handleKeyPress`.
            // ←/→ walk visible tree lines (file or folder); key-repeat is intentional.
            .onKeyPress(phases: [.down, .repeat], action: handleKeyPress)
            .onKeyPress(phases: [.up], action: handleKeyUp)
            .onChange(of: model.readerScrollRequest) { _, request in
                guard let request else {
                    fileJumpController.clearAwaiting()
                    return
                }
                beginFileJump(request, scrollProxy: scrollProxy)
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
                goToNextFile: {
                    trackRapidRepeatBurstAfter(
                        isRepeat: isRepeat,
                        direction: .next
                    ) {
                        model.goToNextFile(isKeyRepeat: isRepeat)
                    }
                },
                goToPreviousFile: {
                    trackRapidRepeatBurstAfter(
                        isRepeat: isRepeat,
                        direction: .previous
                    ) {
                        model.goToPreviousFile(isKeyRepeat: isRepeat)
                    }
                },
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

    private func handleKeyUp(_ keyPress: KeyPress) -> KeyPress.Result {
        switch fileJumpController.rapidRepeatBurstPolicy.handleKeyRelease(
            readerKeyEvent(from: keyPress)
        ) {
        case let .settled(path):
            model.settleReaderScrollOnFile(path: path)
            return .handled
        case .ignored:
            return .ignored
        }
    }

    /// Marks a ←/→ repeat burst when a repeat dispatch issues a new rapid scroll request.
    private func trackRapidRepeatBurstAfter(
        isRepeat: Bool,
        direction: DiffReaderRapidRepeatDirection,
        dispatch: () -> Void
    ) {
        if !isRepeat {
            fileJumpController.rapidRepeatBurstPolicy.noteNonRepeatFileNavigationDispatch()
            dispatch()
            return
        }
        let nonceBefore = model.readerScrollRequest?.nonce
        dispatch()
        fileJumpController.rapidRepeatBurstPolicy.noteRepeatFileNavigationAfterDispatch(
            direction: direction,
            request: model.readerScrollRequest,
            nonceBefore: nonceBefore
        )
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
            currentOffset: scrollGeometryStore.offsetY,
            viewportHeight: scrollGeometryStore.viewportHeight,
            lineHeight: DiffViewerMetric.codeLineHeight,
            intent: intent,
            isRepeat: isRepeat
        )
        scrollPosition.scrollTo(y: target)
    }

    private func beginFileJump(
        _ request: DiffReaderScrollRequest,
        scrollProxy: ScrollViewProxy
    ) {
        fileJumpController.beginJump(request: request)

        let plan = DiffReaderFileJumpPlanner.plan(scrollStyle: request.scrollStyle)
        if case let .identityBootstrap(awaitSentinelCorrection) = plan, awaitSentinelCorrection {
            fileJumpController.awaitingSentinelCorrection = DiffReaderFileJumpAwaiting(
                path: request.path,
                nonce: request.nonce
            )
        }

        let anchorID = DiffFileNavigationResolver.scrollAnchorID(filePath: request.path)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(anchorID, anchor: .top)
        }
    }

    /// Re-runs identity bootstrap when viewport-tall bottom slack replaces the 48pt
    /// placeholder — only while the same settled request is still pending.
    /// Independent of sentinel deferred processing so coalesced geometry work cannot drop it.
    private func scheduleViewportReadyRestart(
        request: DiffReaderScrollRequest,
        scrollProxy: ScrollViewProxy
    ) {
        let nonce = request.nonce
        DispatchQueue.main.async {
            guard let current = model.readerScrollRequest,
                  current.nonce == nonce,
                  current.scrollStyle == .settled
            else { return }
            restartSettledFileJumpIfStillPending(current, scrollProxy: scrollProxy)
        }
    }

    private func restartSettledFileJumpIfStillPending(
        _ request: DiffReaderScrollRequest,
        scrollProxy: ScrollViewProxy
    ) {
        guard let current = model.readerScrollRequest,
              current.nonce == request.nonce,
              current.scrollStyle == .settled
        else { return }
        beginFileJump(request, scrollProxy: scrollProxy)
    }

    private func processPendingSentinelSample() {
        guard let awaiting = fileJumpController.awaitingSentinelCorrection else { return }
        guard fileJumpController.isActive(nonce: awaiting.nonce) else { return }
        guard model.readerScrollRequest?.nonce == awaiting.nonce else { return }
        guard fileJumpController.sampleGeneration > fileJumpController.processedSampleGeneration
        else { return }
        guard let sample = fileJumpController.pendingSample else { return }

        fileJumpController.processedSampleGeneration = fileJumpController.sampleGeneration

        let outcome = DiffReaderBodySentinelSampleProcessor.process(
            sample: sample,
            headerHeight: DiffViewerMetric.headerHeight,
            correctionCount: fileJumpController.correctionCount
        )

        switch outcome {
        case .aligned:
            fileJumpController.clearAwaiting()
            model.clearReaderScrollRequest()
        case let .needsCorrection(targetY):
            fileJumpController.correctionCount += 1
            instantScrollPositionTo(y: targetY)
            fileJumpController.schedulePostCorrectionWatchdog { nonce in
                completeFileJumpAsExhaustedMisaligned(nonce: nonce)
            }
        case .exhaustedMisaligned:
            completeFileJumpAsExhaustedMisaligned(nonce: awaiting.nonce)
        }
    }

    /// Command cleanup after bounded correction exhausts — not an aligned success.
    private func completeFileJumpAsExhaustedMisaligned(nonce: UInt) {
        guard fileJumpController.isActive(nonce: nonce) else { return }
        guard fileJumpController.awaitingSentinelCorrection != nil else { return }
        fileJumpController.exhaustedMisaligned = true
        fileJumpController.clearAwaiting()
        model.clearReaderScrollRequest()
    }

    private func instantScrollPositionTo(y: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition.scrollTo(y: y)
        }
    }
}

// MARK: - Keyboard

/// Snapshot of the reader's scroll geometry for `onScrollGeometryChange`.
private struct DiffReaderVisibleScroll: Equatable {
    var offsetY: CGFloat
    var viewportHeight: CGFloat
    var viewportWidth: CGFloat
    var contentHeight: CGFloat
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
