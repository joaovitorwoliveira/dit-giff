import CoreGraphics

/// Sub-point slack for scroll geometry — Retina float noise must not republish
/// observed dimensions every layout pass.
nonisolated enum DiffReaderScrollGeometryTolerance {
    static let dimension: CGFloat = 0.5
    /// Ignore sub-point viewport jitter after the first measurement — bottom slack
    /// padding must not chase `onGeometryChange` noise and re-layout the scroll content.
    static let viewportResizeLatch: CGFloat = 2
}

/// Named coordinate space on the reader scroll content root. Sentinel geometry reports
/// `contentMinY` in this space so scroll targets are independent of scroll-offset callback order.
nonisolated enum DiffReaderScrollContentSpace {
    static let name = "diff-reader-scroll-content"
}

/// Latest scroll geometry from `onScrollGeometryChange` — reference storage for paging only.
@MainActor
final class DiffReaderScrollGeometryStore {
    private(set) var offsetY: CGFloat = 0
    private(set) var viewportHeight: CGFloat = 0
    private(set) var viewportWidth: CGFloat = 0
    private(set) var contentHeight: CGFloat = 0

    /// Returns whether any stored dimension changed. Quantizes width to whole points so
    /// wrap invalidation reacts to real column resize, not subpixel jitter.
    @discardableResult
    func update(
        offsetY: CGFloat,
        viewportHeight: CGFloat,
        viewportWidth: CGFloat,
        contentHeight: CGFloat
    ) -> Bool {
        let quantizedWidth = floor(viewportWidth)
        guard
            !dimensionsMatch(offsetY, self.offsetY)
            || !dimensionsMatch(viewportHeight, self.viewportHeight)
            || !dimensionsMatch(quantizedWidth, self.viewportWidth)
            || !dimensionsMatch(contentHeight, self.contentHeight)
        else {
            return false
        }
        self.offsetY = offsetY
        self.viewportHeight = viewportHeight
        self.viewportWidth = quantizedWidth
        self.contentHeight = contentHeight
        return true
    }

    private func dimensionsMatch(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= DiffReaderScrollGeometryTolerance.dimension
    }
}

/// In-flight settled jump waiting for the target body-start sentinel geometry.
nonisolated struct DiffReaderFileJumpAwaiting: Equatable, Sendable {
    var path: String
    var nonce: UInt
}

/// One body-start sentinel geometry sample — viewport position for alignment confirmation
/// and content-space position for scroll target math.
nonisolated struct DiffReaderBodySentinelSample: Equatable, Sendable {
    var viewportMinY: CGFloat
    var contentMinY: CGFloat
}

/// Alignment of the body-start sentinel relative to the reader viewport top.
///
/// When settled, the sentinel sits `headerHeight` below the viewport top — the sticky
/// file header is flush with Y zero and the body begins directly beneath it.
nonisolated enum DiffReaderBodySentinelAlignment {
    static let tolerance: CGFloat = 1

    static func absoluteScrollTargetY(
        sentinelContentMinY: CGFloat,
        headerHeight: CGFloat
    ) -> CGFloat {
        max(0, sentinelContentMinY - headerHeight)
    }

    static func isWithinTolerance(
        sentinelViewportMinY: CGFloat,
        headerHeight: CGFloat
    ) -> Bool {
        abs(sentinelViewportMinY - headerHeight) <= tolerance
    }
}

/// Point corrections per settled jump — bootstrap + one correction is the usual case;
/// a second pass covers SwiftUI clamping without an infinite loop.
nonisolated enum DiffReaderFileJumpCorrectionBounds {
    static let maxPointCorrectionsPerRequest = 2
}

/// Pure decision for one file jump: identity `scrollTo` bootstrap, optionally followed
/// by sentinel-based point correction(s).
nonisolated enum DiffReaderFileJumpPlan: Equatable, Sendable {
    case identityBootstrap(awaitSentinelCorrection: Bool)
}

nonisolated enum DiffReaderFileJumpPlanner {
    static func plan(scrollStyle: DiffReaderFileScrollStyle) -> DiffReaderFileJumpPlan {
        switch scrollStyle {
        case .settled:
            return .identityBootstrap(awaitSentinelCorrection: true)
        case .rapid:
            return .identityBootstrap(awaitSentinelCorrection: false)
        }
    }
}

/// Outcome of processing one body-sentinel geometry sample during a settled jump.
nonisolated enum DiffReaderBodySentinelSampleOutcome: Equatable, Sendable {
    case aligned
    case needsCorrection(targetOffsetY: CGFloat)
    case exhaustedMisaligned
}

/// Horizontal file-navigation direction for ←/→ repeat bursts.
nonisolated enum DiffReaderRapidRepeatDirection: Equatable, Sendable {
    case previous
    case next
}

/// Active ←/→ key-repeat burst waiting for a matching bare arrow key-up.
nonisolated struct DiffReaderRapidRepeatBurst: Equatable, Sendable {
    var direction: DiffReaderRapidRepeatDirection
    var lastFilePath: String
}

/// Key-up phase of a reader shortcut — same shape as `DiffReaderKeyEvent` so tests
/// exercise the release policy `DiffViewer.handleKeyUp` calls.
typealias DiffReaderKeyReleaseEvent = DiffReaderKeyEvent

/// Outcome of handling one key-up during a ←/→ repeat burst.
nonisolated enum DiffReaderRapidRepeatBurstReleaseOutcome: Equatable, Sendable {
    case settled(path: String)
    case ignored
}

/// Pure ←/→ repeat-burst tracking: mark on repeat dispatch, settle on matching release.
nonisolated struct DiffReaderRapidRepeatBurstPolicy: Equatable, Sendable {
    private(set) var burst: DiffReaderRapidRepeatBurst?

    mutating func clear() {
        burst = nil
    }

    /// Non-repeat ←/→ down clears any stale burst before dispatch.
    mutating func noteNonRepeatFileNavigationDispatch() {
        burst = nil
    }

    /// Repeat ←/→ down after dispatch — clears a stale burst when the reader has no request
    /// (file unavailable in the reader column). Folder steps keep the prior rapid request.
    mutating func noteRepeatFileNavigationAfterDispatch(
        direction: DiffReaderRapidRepeatDirection,
        request: DiffReaderScrollRequest?,
        nonceBefore: UInt?
    ) {
        guard let request else {
            burst = nil
            return
        }
        let producedNewRapidRequest = request.scrollStyle == .rapid && request.nonce != nonceBefore
        noteRepeatFileNavigationDispatch(
            direction: direction,
            producedNewRapidRequest: producedNewRapidRequest,
            filePath: request.path
        )
    }

    /// Repeat ←/→ down that issued a new rapid scroll request extends the burst.
    mutating func noteRepeatFileNavigationDispatch(
        direction: DiffReaderRapidRepeatDirection,
        producedNewRapidRequest: Bool,
        filePath: String
    ) {
        guard producedNewRapidRequest else { return }
        burst = DiffReaderRapidRepeatBurst(direction: direction, lastFilePath: filePath)
    }

    mutating func handleKeyRelease(
        _ event: DiffReaderKeyReleaseEvent
    ) -> DiffReaderRapidRepeatBurstReleaseOutcome {
        if event.modifiers.shift
            || event.modifiers.command
            || event.modifiers.option
            || event.modifiers.control
        {
            burst = nil
            return .ignored
        }

        switch event.key {
        case .leftArrow:
            guard let active = burst else { return .ignored }
            burst = nil
            guard active.direction == .previous else { return .ignored }
            return .settled(path: active.lastFilePath)
        case .rightArrow:
            guard let active = burst else { return .ignored }
            burst = nil
            guard active.direction == .next else { return .ignored }
            return .settled(path: active.lastFilePath)
        default:
            return .ignored
        }
    }
}

/// Bounded post-correction watchdog — when a point scroll is clamped to a no-op,
/// geometry may never emit a fresh sample. Terminate as exhausted only while the
/// same nonce is still awaiting and sample generation has not advanced.
nonisolated enum DiffReaderFileJumpPostCorrectionWatchdog {
    static func shouldTerminateAsExhaustedMisaligned(
        capturedNonce: UInt,
        capturedProcessedGeneration: UInt,
        activeNonce: UInt?,
        awaitingCorrection: DiffReaderFileJumpAwaiting?,
        sampleGeneration: UInt,
        processedSampleGeneration: UInt
    ) -> Bool {
        guard activeNonce == capturedNonce else { return false }
        guard let awaitingCorrection, awaitingCorrection.nonce == capturedNonce else { return false }
        guard sampleGeneration == capturedProcessedGeneration else { return false }
        return processedSampleGeneration == capturedProcessedGeneration
    }
}

nonisolated enum DiffReaderBodySentinelSampleProcessor {
    static func process(
        sample: DiffReaderBodySentinelSample,
        headerHeight: CGFloat,
        correctionCount: Int
    ) -> DiffReaderBodySentinelSampleOutcome {
        if DiffReaderBodySentinelAlignment.isWithinTolerance(
            sentinelViewportMinY: sample.viewportMinY,
            headerHeight: headerHeight
        ) {
            return .aligned
        }

        guard correctionCount < DiffReaderFileJumpCorrectionBounds.maxPointCorrectionsPerRequest
        else {
            return .exhaustedMisaligned
        }

        let target = DiffReaderBodySentinelAlignment.absoluteScrollTargetY(
            sentinelContentMinY: sample.contentMinY,
            headerHeight: headerHeight
        )
        return .needsCorrection(targetOffsetY: target)
    }
}

/// Reference storage for file-jump geometry samples and in-flight correction state.
/// Geometry callbacks write here instead of `@State` so layout does not re-render per sample.
@MainActor
final class DiffReaderFileJumpController {
    var awaitingSentinelCorrection: DiffReaderFileJumpAwaiting?
    var pendingSample: DiffReaderBodySentinelSample?
    var sampleGeneration: UInt = 0
    var processedSampleGeneration: UInt = 0
    var correctionCount = 0
    var exhaustedMisaligned = false
    var activeNonce: UInt?
    var rapidRepeatBurstPolicy = DiffReaderRapidRepeatBurstPolicy()
    private var deferredProcessingScheduled = false

    func beginJump(request: DiffReaderScrollRequest) {
        awaitingSentinelCorrection = nil
        pendingSample = nil
        sampleGeneration = 0
        processedSampleGeneration = 0
        correctionCount = 0
        exhaustedMisaligned = false
        activeNonce = request.nonce
    }

    func clearAwaiting() {
        awaitingSentinelCorrection = nil
        pendingSample = nil
        sampleGeneration = 0
        processedSampleGeneration = 0
        correctionCount = 0
        exhaustedMisaligned = false
        activeNonce = nil
    }

    func isActive(nonce: UInt) -> Bool {
        activeNonce == nonce
    }

    /// Records a sentinel sample only when it matches the active awaiting path/nonce.
    /// Returns whether a fresh sample was stored (caller may schedule deferred processing).
    func recordSentinelSample(path: String, sample: DiffReaderBodySentinelSample) -> Bool {
        guard !exhaustedMisaligned else { return false }
        guard let awaiting = awaitingSentinelCorrection,
              awaiting.path == path,
              isActive(nonce: awaiting.nonce)
        else {
            return false
        }
        pendingSample = sample
        sampleGeneration += 1
        return true
    }

    /// Schedules sentinel processing on the next main-queue turn — never inside
    /// `onGeometryChange` or `onScrollGeometryChange`.
    func scheduleDeferredProcessing(_ process: @escaping @MainActor () -> Void) {
        guard !deferredProcessingScheduled else { return }
        deferredProcessingScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deferredProcessingScheduled = false
            process()
        }
    }

    /// After a point correction, wait two main-queue turns for a fresh sentinel sample.
    /// If generation is still unchanged, invoke `onExhausted` with the captured nonce.
    func schedulePostCorrectionWatchdog(onExhausted: @escaping @MainActor (UInt) -> Void) {
        guard let capturedNonce = activeNonce else { return }
        let capturedGeneration = processedSampleGeneration
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                guard DiffReaderFileJumpPostCorrectionWatchdog.shouldTerminateAsExhaustedMisaligned(
                    capturedNonce: capturedNonce,
                    capturedProcessedGeneration: capturedGeneration,
                    activeNonce: self.activeNonce,
                    awaitingCorrection: self.awaitingSentinelCorrection,
                    sampleGeneration: self.sampleGeneration,
                    processedSampleGeneration: self.processedSampleGeneration
                ) else {
                    return
                }
                onExhausted(capturedNonce)
            }
        }
    }
}
