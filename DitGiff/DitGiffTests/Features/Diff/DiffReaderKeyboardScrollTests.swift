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

    @Test func arrowsStepOneLineWithoutShift() {
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

    @Test func lineStepsUseLineHeight() {
        #expect(
            DiffReaderScrollPaging.targetOffset(
                currentOffset: 100,
                viewportHeight: 400,
                lineHeight: 20.15,
                intent: .lineDown
            ) == 120.15
        )
        #expect(
            DiffReaderScrollPaging.targetOffset(
                currentOffset: 100,
                viewportHeight: 400,
                lineHeight: 20.15,
                intent: .lineUp
            ) == 79.85
        )
    }
}
