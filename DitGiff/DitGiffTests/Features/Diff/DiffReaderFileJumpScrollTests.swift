import CoreGraphics
import Testing

@testable import DitGiff

@MainActor
struct DiffReaderFileJumpScrollTests {
    // MARK: - Geometry store

    @Test func scrollGeometryStorePublishesMaterialChangesOnly() {
        let store = DiffReaderScrollGeometryStore()
        #expect(
            store.update(
                offsetY: 10,
                viewportHeight: 600,
                viewportWidth: 871.4,
                contentHeight: 4_000
            )
        )
        #expect(store.viewportWidth == 871)
        #expect(
            !store.update(
                offsetY: 10.2,
                viewportHeight: 600.2,
                viewportWidth: 871.9,
                contentHeight: 4_000.2
            )
        )
        #expect(
            store.update(
                offsetY: 80,
                viewportHeight: 600,
                viewportWidth: 871,
                contentHeight: 4_000
            )
        )
    }

    // MARK: - Awaiting identity

    @Test func awaitingIdentityTracksPathAndNonce() {
        let first = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 1)
        let same = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 1)
        let next = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 2)
        #expect(first == same)
        #expect(first != next)
    }

    // MARK: - Body-sentinel correction math

    @Test func absoluteScrollTargetWithCorrectNamedSpace() {
        let headerHeight: CGFloat = 48
        let target = DiffReaderBodySentinelAlignment.absoluteScrollTargetY(
            sentinelContentMinY: 580,
            headerHeight: headerHeight
        )
        #expect(target == 532)
    }

    @Test func absoluteScrollTargetDoesNotDependOnScrollOffset() {
        let headerHeight: CGFloat = 48
        let contentMinY: CGFloat = 580
        let target = DiffReaderBodySentinelAlignment.absoluteScrollTargetY(
            sentinelContentMinY: contentMinY,
            headerHeight: headerHeight
        )
        // A stale scroll offset cannot enter this API — same contentMinY always yields
        // the same target regardless of what paging offset the store might hold.
        #expect(target == max(0, contentMinY - headerHeight))
        #expect(target == 532)
    }

    @Test func alignedViewportSampleCompletes() {
        let headerHeight: CGFloat = 48
        let outcome = DiffReaderBodySentinelSampleProcessor.process(
            sample: DiffReaderBodySentinelSample(viewportMinY: headerHeight, contentMinY: 1_000),
            headerHeight: headerHeight,
            correctionCount: 0
        )
        #expect(outcome == .aligned)
    }

    @Test func alignedSentinelWithinToleranceCompletes() {
        let headerHeight: CGFloat = 48
        let outcome = DiffReaderBodySentinelSampleProcessor.process(
            sample: DiffReaderBodySentinelSample(
                viewportMinY: headerHeight + 0.5,
                contentMinY: 200
            ),
            headerHeight: headerHeight,
            correctionCount: 0
        )
        #expect(outcome == .aligned)
    }

    @Test func misalignedSentinelProducesContentBasedCorrection() {
        let headerHeight: CGFloat = 48
        let outcome = DiffReaderBodySentinelSampleProcessor.process(
            sample: DiffReaderBodySentinelSample(viewportMinY: 120, contentMinY: 520),
            headerHeight: headerHeight,
            correctionCount: 0
        )
        #expect(outcome == .needsCorrection(targetOffsetY: 472))
    }

    @Test func staleScrollOffsetCannotAffectCorrectionInput() {
        let headerHeight: CGFloat = 48
        let sample = DiffReaderBodySentinelSample(viewportMinY: 120, contentMinY: 520)
        let outcome = DiffReaderBodySentinelSampleProcessor.process(
            sample: sample,
            headerHeight: headerHeight,
            correctionCount: 0
        )
        guard case let .needsCorrection(targetOffsetY) = outcome else {
            Issue.record("expected correction outcome")
            return
        }
        // contentMinY 520 − header 48 — no scroll-offset term exists in the processor.
        #expect(targetOffsetY == 472)
        #expect(targetOffsetY != 520)
        #expect(targetOffsetY != 120)
    }

    // MARK: - Sticky-header assumptions removed

    @Test func headerViewportZeroIsNotTreatedAsAlignedSentinel() {
        let headerHeight: CGFloat = 48
        #expect(
            !DiffReaderBodySentinelAlignment.isWithinTolerance(
                sentinelViewportMinY: 0,
                headerHeight: headerHeight
            )
        )
        let outcome = DiffReaderBodySentinelSampleProcessor.process(
            sample: DiffReaderBodySentinelSample(viewportMinY: 0, contentMinY: 900),
            headerHeight: headerHeight,
            correctionCount: 0
        )
        #expect(outcome == .needsCorrection(targetOffsetY: 852))
    }

    // MARK: - Fresh sample sequencing

    @Test func everyCorrectionRequiresFreshSampleGeneration() {
        let controller = DiffReaderFileJumpController()
        controller.beginJump(
            request: DiffReaderScrollRequest(path: "a.swift", nonce: 1, scrollStyle: .settled)
        )
        controller.awaitingSentinelCorrection = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 1)

        let misaligned = DiffReaderBodySentinelSample(viewportMinY: 200, contentMinY: 300)
        #expect(controller.recordSentinelSample(path: "a.swift", sample: misaligned))
        #expect(controller.sampleGeneration == 1)
        #expect(controller.sampleGeneration > controller.processedSampleGeneration)

        // Simulate processing the first sample.
        controller.processedSampleGeneration = controller.sampleGeneration
        controller.correctionCount = 1

        // Without a new geometry callback, generation is stale — no second decision.
        #expect(controller.sampleGeneration == controller.processedSampleGeneration)

        let fresh = DiffReaderBodySentinelSample(viewportMinY: 200, contentMinY: 310)
        #expect(controller.recordSentinelSample(path: "a.swift", sample: fresh))
        #expect(controller.sampleGeneration == 2)
        #expect(controller.sampleGeneration > controller.processedSampleGeneration)
    }

    @Test func noActiveJumpSentinelSampleIsIgnored() {
        let controller = DiffReaderFileJumpController()
        let sample = DiffReaderBodySentinelSample(viewportMinY: 48, contentMinY: 100)
        #expect(!controller.recordSentinelSample(path: "a.swift", sample: sample))
        #expect(controller.pendingSample == nil)
        #expect(controller.sampleGeneration == 0)
    }

    // MARK: - Nonce and bounds

    @Test func latestNonceCancelsStaleJumpWork() {
        let controller = DiffReaderFileJumpController()
        controller.beginJump(
            request: DiffReaderScrollRequest(path: "a.swift", nonce: 1, scrollStyle: .settled)
        )
        controller.awaitingSentinelCorrection = DiffReaderFileJumpAwaiting(
            path: "a.swift",
            nonce: 1
        )
        controller.beginJump(
            request: DiffReaderScrollRequest(path: "b.swift", nonce: 2, scrollStyle: .settled)
        )
        #expect(controller.isActive(nonce: 1) == false)
        #expect(controller.isActive(nonce: 2))
        #expect(controller.awaitingSentinelCorrection == nil)
        let staleSample = DiffReaderBodySentinelSample(viewportMinY: 48, contentMinY: 100)
        #expect(!controller.recordSentinelSample(path: "a.swift", sample: staleSample))
    }

    @Test func exhaustedBudgetIsExhaustedMisalignedNotAligned() {
        let headerHeight: CGFloat = 48
        var correctionCount = 0
        let misaligned = DiffReaderBodySentinelSample(viewportMinY: 200, contentMinY: 300)

        let first = DiffReaderBodySentinelSampleProcessor.process(
            sample: misaligned,
            headerHeight: headerHeight,
            correctionCount: correctionCount
        )
        guard case .needsCorrection = first else {
            Issue.record("expected first correction")
            return
        }
        correctionCount += 1

        let second = DiffReaderBodySentinelSampleProcessor.process(
            sample: misaligned,
            headerHeight: headerHeight,
            correctionCount: correctionCount
        )
        guard case .needsCorrection = second else {
            Issue.record("expected second correction")
            return
        }
        correctionCount += 1

        let third = DiffReaderBodySentinelSampleProcessor.process(
            sample: misaligned,
            headerHeight: headerHeight,
            correctionCount: correctionCount
        )
        #expect(third == .exhaustedMisaligned)
        #expect(third != .aligned)
    }

    // MARK: - Jump planner

    @Test func settledPlanAwaitSentinelCorrection() {
        let plan = DiffReaderFileJumpPlanner.plan(scrollStyle: .settled)
        #expect(plan == .identityBootstrap(awaitSentinelCorrection: true))
    }

    @Test func rapidPlanSkipsSentinelCorrection() {
        let plan = DiffReaderFileJumpPlanner.plan(scrollStyle: .rapid)
        #expect(plan == .identityBootstrap(awaitSentinelCorrection: false))
    }

    // MARK: - Bottom slack

    @Test func lastFileBottomSlackPrefersViewportHeight() {
        #expect(
            DiffReaderFileJumpLayout.bottomScrollSlack(
                viewportHeight: 800,
                minimumPadding: 48
            ) == 800
        )
        #expect(
            DiffReaderFileJumpLayout.bottomScrollSlack(
                viewportHeight: 0,
                minimumPadding: 48
            ) == 48
        )
    }

    // MARK: - Repeat burst (policy)

    @Test func matchingArrowReleaseSettlesBurstPath() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: "a.swift"
        )
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .rightArrow, modifiers: .init())
        )
        #expect(outcome == .settled(path: "a.swift"))
        #expect(policy.burst == nil)
    }

    @Test func bareArrowReleaseWithoutBurstIsIgnored() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .rightArrow, modifiers: .init())
        )
        #expect(outcome == .ignored)
    }

    @Test func modifiedArrowReleaseClearsBurstWithoutSettling() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: "a.swift"
        )
        let shiftOutcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .rightArrow, modifiers: .init(shift: true))
        )
        #expect(shiftOutcome == .ignored)
        #expect(policy.burst == nil)

        policy.noteRepeatFileNavigationDispatch(
            direction: .previous,
            producedNewRapidRequest: true,
            filePath: "b.swift"
        )
        let commandOutcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .leftArrow, modifiers: .init(command: true))
        )
        #expect(commandOutcome == .ignored)
        #expect(policy.burst == nil)
    }

    @Test func oppositeArrowReleaseClearsBurstWithoutSettling() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: "a.swift"
        )
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .leftArrow, modifiers: .init())
        )
        #expect(outcome == .ignored)
        #expect(policy.burst == nil)
    }

    @Test func nonArrowReleaseDoesNotSettleOrClearBurst() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: "a.swift"
        )
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .space, modifiers: .init())
        )
        #expect(outcome == .ignored)
        #expect(policy.burst?.lastFilePath == "a.swift")
    }

    @Test func nonRepeatDispatchClearsStaleBurst() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: "a.swift"
        )
        policy.noteNonRepeatFileNavigationDispatch()
        #expect(policy.burst == nil)
    }

    @Test func repeatDispatchWithoutNewRapidRequestDoesNotMarkBurst() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: false,
            filePath: "a.swift"
        )
        #expect(policy.burst == nil)
    }

    @Test func repeatDispatchClearsBurstWhenReaderRequestUnavailable() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: "a.swift"
        )
        policy.noteRepeatFileNavigationAfterDispatch(
            direction: .next,
            request: nil,
            nonceBefore: 1
        )
        #expect(policy.burst == nil)
    }

    @Test func repeatDispatchKeepsBurstOnFolderStepWithoutNewRequest() {
        var policy = DiffReaderRapidRepeatBurstPolicy()
        let rapidRequest = DiffReaderScrollRequest(
            path: "Sources/Billing/ProrationCalculator.swift",
            nonce: 2,
            scrollStyle: .rapid
        )
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: rapidRequest.path
        )
        policy.noteRepeatFileNavigationAfterDispatch(
            direction: .next,
            request: rapidRequest,
            nonceBefore: 2
        )
        #expect(policy.burst?.lastFilePath == rapidRequest.path)
    }

    @Test func exhaustedMisalignedStopsRecordingSamples() {
        let controller = DiffReaderFileJumpController()
        controller.beginJump(
            request: DiffReaderScrollRequest(path: "a.swift", nonce: 1, scrollStyle: .settled)
        )
        controller.awaitingSentinelCorrection = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 1)
        controller.exhaustedMisaligned = true
        let sample = DiffReaderBodySentinelSample(viewportMinY: 200, contentMinY: 300)
        #expect(!controller.recordSentinelSample(path: "a.swift", sample: sample))
    }

    // MARK: - Post-correction watchdog

    @Test func noProgressWatchdogRequiresSameNonceAwaitingAndUnchangedGeneration() {
        let awaiting = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 3)
        #expect(
            DiffReaderFileJumpPostCorrectionWatchdog.shouldTerminateAsExhaustedMisaligned(
                capturedNonce: 3,
                capturedProcessedGeneration: 2,
                activeNonce: 3,
                awaitingCorrection: awaiting,
                sampleGeneration: 2,
                processedSampleGeneration: 2
            )
        )
        #expect(
            !DiffReaderFileJumpPostCorrectionWatchdog.shouldTerminateAsExhaustedMisaligned(
                capturedNonce: 3,
                capturedProcessedGeneration: 2,
                activeNonce: 4,
                awaitingCorrection: awaiting,
                sampleGeneration: 2,
                processedSampleGeneration: 2
            )
        )
        #expect(
            !DiffReaderFileJumpPostCorrectionWatchdog.shouldTerminateAsExhaustedMisaligned(
                capturedNonce: 3,
                capturedProcessedGeneration: 2,
                activeNonce: 3,
                awaitingCorrection: nil,
                sampleGeneration: 2,
                processedSampleGeneration: 2
            )
        )
        #expect(
            !DiffReaderFileJumpPostCorrectionWatchdog.shouldTerminateAsExhaustedMisaligned(
                capturedNonce: 3,
                capturedProcessedGeneration: 2,
                activeNonce: 3,
                awaitingCorrection: awaiting,
                sampleGeneration: 3,
                processedSampleGeneration: 3
            )
        )
    }

    @Test func generationAdvancePreventsStaleWatchdogExhaustion() {
        let awaiting = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 1)
        #expect(
            !DiffReaderFileJumpPostCorrectionWatchdog.shouldTerminateAsExhaustedMisaligned(
                capturedNonce: 1,
                capturedProcessedGeneration: 1,
                activeNonce: 1,
                awaitingCorrection: awaiting,
                sampleGeneration: 2,
                processedSampleGeneration: 2
            )
        )
    }

    @Test func newerNoncePreventsStaleWatchdogCleanup() {
        let staleAwaiting = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 1)
        #expect(
            !DiffReaderFileJumpPostCorrectionWatchdog.shouldTerminateAsExhaustedMisaligned(
                capturedNonce: 1,
                capturedProcessedGeneration: 1,
                activeNonce: 2,
                awaitingCorrection: staleAwaiting,
                sampleGeneration: 1,
                processedSampleGeneration: 1
            )
        )
    }

    @Test func controllerTeardownAfterExhaustedAcceptsNewNonce() {
        let controller = DiffReaderFileJumpController()
        controller.beginJump(
            request: DiffReaderScrollRequest(path: "a.swift", nonce: 1, scrollStyle: .settled)
        )
        controller.awaitingSentinelCorrection = DiffReaderFileJumpAwaiting(path: "a.swift", nonce: 1)
        controller.exhaustedMisaligned = true
        controller.clearAwaiting()

        controller.beginJump(
            request: DiffReaderScrollRequest(path: "b.swift", nonce: 2, scrollStyle: .settled)
        )
        controller.awaitingSentinelCorrection = DiffReaderFileJumpAwaiting(path: "b.swift", nonce: 2)
        #expect(controller.isActive(nonce: 2))
        #expect(!controller.exhaustedMisaligned)
        #expect(controller.recordSentinelSample(
            path: "b.swift",
            sample: DiffReaderBodySentinelSample(viewportMinY: 48, contentMinY: 100)
        ))
    }

    // MARK: - Key-up settled request (model)

    @Test func repeatNavigationThenKeyReleaseIssuesSettledRequestForLastRapidFile() throws {
        let model = makeModel()
        let first = try #require(
            model.file(atPath: "Sources/Billing/BillingConfig.swift")
        )
        let second = try #require(
            model.file(atPath: "Sources/Billing/BillingGuard.swift")
        )
        let third = try #require(
            model.file(atPath: "Sources/Billing/InvoiceScheduler.swift")
        )
        model.revealFileInReader(first)
        let firstNonce = try #require(model.readerScrollRequest?.nonce)

        model.goToNextFile(isKeyRepeat: true)
        let secondRequest = try #require(model.readerScrollRequest)
        #expect(model.focusedFilePath == second.path)

        model.goToNextFile(isKeyRepeat: true)
        let thirdRequest = try #require(model.readerScrollRequest)
        #expect(model.focusedFilePath == third.path)
        #expect(thirdRequest.scrollStyle == .rapid)
        #expect(thirdRequest.nonce != firstNonce)
        #expect(thirdRequest.nonce != secondRequest.nonce)

        model.settleReaderScrollOnFile(path: third.path)
        let settled = try #require(model.readerScrollRequest)
        #expect(model.focusedFilePath == third.path)
        #expect(settled.path == third.path)
        #expect(settled.scrollStyle == .settled)
        #expect(settled.nonce != thirdRequest.nonce)
    }

    @Test func singleNonRepeatArrowProducesOneSettledRequestOnly() throws {
        let model = makeModel()
        let config = try #require(model.file(atPath: "Sources/Billing/BillingConfig.swift"))
        model.revealFileInReader(config)
        model.clearReaderScrollRequest()

        model.goToNextFile(isKeyRepeat: false)
        let settled = try #require(model.readerScrollRequest)
        #expect(settled.scrollStyle == .settled)
        let nonceAfterDown = settled.nonce

        // Simulates key-up with no repeat burst — request must stay unchanged.
        var policy = DiffReaderRapidRepeatBurstPolicy()
        let outcome = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .rightArrow, modifiers: .init())
        )
        #expect(outcome == .ignored)
        #expect(model.readerScrollRequest?.nonce == nonceAfterDown)
    }

    @Test func repeatBurstEndingOnFolderSettlesLastRapidFileNotFolder() throws {
        let model = makeModel()
        let planResolver = try #require(
            model.file(atPath: "Sources/Billing/PlanResolver.swift")
        )
        let proration = try #require(
            model.file(atPath: "Sources/Billing/ProrationCalculator.swift")
        )
        model.revealFileInReader(planResolver)
        model.clearReaderScrollRequest()

        model.goToNextFile(isKeyRepeat: true)
        let rapidRequest = try #require(model.readerScrollRequest)
        #expect(rapidRequest.scrollStyle == .rapid)
        #expect(rapidRequest.path == proration.path)

        model.goToNextFile(isKeyRepeat: false)
        #expect(model.focusedFilePath == "Sources/HTTP/")
        #expect(model.readerScrollRequest?.path == proration.path)
        #expect(model.readerScrollRequest?.scrollStyle == .rapid)

        var policy = DiffReaderRapidRepeatBurstPolicy()
        policy.noteRepeatFileNavigationDispatch(
            direction: .next,
            producedNewRapidRequest: true,
            filePath: rapidRequest.path
        )
        let release = policy.handleKeyRelease(
            DiffReaderKeyReleaseEvent(key: .rightArrow, modifiers: .init())
        )
        #expect(release == .settled(path: rapidRequest.path))

        model.settleReaderScrollOnFile(path: rapidRequest.path)
        let settled = try #require(model.readerScrollRequest)
        #expect(settled.path == proration.path)
        #expect(settled.path != "Sources/HTTP/")
        #expect(settled.scrollStyle == .settled)
        #expect(model.focusedFilePath == "Sources/HTTP/")
    }

    @Test func folderReleaseWithoutBurstIsNoOp() throws {
        let model = makeModel()
        model.focusTreeLine("Sources/Billing/")
        model.settleReaderScrollOnFile(path: "Sources/Billing/")
        #expect(model.readerScrollRequest == nil)
        #expect(model.focusedFilePath == "Sources/Billing/")
    }

    @Test func settleOnDirectoryPathIsNoOp() {
        let model = makeModel()
        model.settleReaderScrollOnFile(path: "Sources/Billing/")
        #expect(model.readerScrollRequest == nil)
    }

    private func makeModel() -> DiffModel {
        DiffModel(
            replyDelay: ImmediateReplyDelay(),
            readHunkBaseline: DiffSampleData.readHunkBaseline
        )
    }
}

private struct ImmediateReplyDelay: DiffReplyDelay {
    func wait() async throws {}
}
