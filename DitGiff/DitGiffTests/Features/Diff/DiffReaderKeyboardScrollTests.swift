import CoreGraphics
import Testing

@testable import DitGiff

struct DiffReaderKeyboardScrollTests {
    // MARK: - Key mapping

    @Test func spacePagesDown() {
        let intent = DiffReaderScrollKeyMapping.intent(
            for: DiffReaderScrollKeyEvent(kind: .space, shift: false)
        )
        #expect(intent == .pageDown)
    }

    @Test func shiftSpacePagesUp() {
        let intent = DiffReaderScrollKeyMapping.intent(
            for: DiffReaderScrollKeyEvent(kind: .space, shift: true)
        )
        #expect(intent == .pageUp)
    }

    @Test func pageKeysMapWithoutShift() {
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .pageDown, shift: false)
            ) == .pageDown
        )
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .pageUp, shift: false)
            ) == .pageUp
        )
    }

    @Test func shiftOnPageKeysIsIgnored() {
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .pageDown, shift: true)
            ) == nil
        )
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .pageUp, shift: true)
            ) == nil
        )
    }

    @Test func arrowsMapToLineStepsWithoutShift() {
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .downArrow, shift: false)
            ) == .lineDown
        )
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .upArrow, shift: false)
            ) == .lineUp
        )
    }

    @Test func shiftArrowsAreIgnored() {
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .downArrow, shift: true)
            ) == nil
        )
        #expect(
            DiffReaderScrollKeyMapping.intent(
                for: DiffReaderScrollKeyEvent(kind: .upArrow, shift: true)
            ) == nil
        )
    }

    // MARK: - Letter shortcuts

    @Test func nAndVStillMapToLetterActions() {
        #expect(
            DiffReaderLetterKeyMapping.action(for: DiffReaderLetterKey.nextUnreadFile)
                == .nextUnreadFile
        )
        #expect(
            DiffReaderLetterKeyMapping.action(for: DiffReaderLetterKey.toggleViewed)
                == .toggleViewed
        )
    }

    @Test func jkProduceNoReaderIntent() {
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .character("j"), modifiers: .init())
            ) == nil
        )
        #expect(
            DiffReaderKeyIntentMapping.intent(
                for: DiffReaderKeyEvent(key: .character("k"), modifiers: .init())
            ) == nil
        )
    }

    // MARK: - Offset

    @Test func pageDownAdvancesByViewportFraction() {
        let target = DiffReaderScrollPaging.targetOffset(
            currentOffset: 100,
            viewportHeight: 400,
            lineHeight: 20,
            intent: .pageDown
        )
        #expect(target == 100 + 400 * DiffReaderScrollPaging.pageViewportFraction)
    }

    @Test func pageUpRetreatsAndClampsAtZero() {
        let target = DiffReaderScrollPaging.targetOffset(
            currentOffset: 50,
            viewportHeight: 400,
            lineHeight: 20,
            intent: .pageUp
        )
        #expect(target == 0)
    }

    @Test func lineStepsAdvanceByFiveLineHeightsOnSinglePress() {
        let lineHeight: CGFloat = 20.15
        #expect(DiffReaderScrollPaging.arrowLineStepCount == 5)
        #expect(DiffReaderScrollPaging.lineStepCount(isRepeat: false) == 5)
        #expect(
            DiffReaderScrollPaging.targetOffset(
                currentOffset: 200,
                viewportHeight: 400,
                lineHeight: lineHeight,
                intent: .lineDown
            ) == 200 + lineHeight * 5
        )
        #expect(
            DiffReaderScrollPaging.targetOffset(
                currentOffset: 200,
                viewportHeight: 400,
                lineHeight: lineHeight,
                intent: .lineUp
            ) == 200 - lineHeight * 5
        )
    }

    @Test func lineStepsAdvanceByThreeLineHeightsOnRepeat() {
        let lineHeight: CGFloat = 20.15
        #expect(DiffReaderScrollPaging.arrowLineRepeatStepCount == 3)
        #expect(DiffReaderScrollPaging.lineStepCount(isRepeat: true) == 3)
        #expect(
            DiffReaderScrollPaging.targetOffset(
                currentOffset: 200,
                viewportHeight: 400,
                lineHeight: lineHeight,
                intent: .lineDown,
                isRepeat: true
            ) == 200 + lineHeight * 3
        )
        #expect(
            DiffReaderScrollPaging.targetOffset(
                currentOffset: 200,
                viewportHeight: 400,
                lineHeight: lineHeight,
                intent: .lineUp,
                isRepeat: true
            ) == 200 - lineHeight * 3
        )
    }
}
