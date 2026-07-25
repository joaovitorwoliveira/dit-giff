import Testing

@testable import DitGiff

struct DiffCodeSelectionHitTestingTests {
    private let fallback = 20.0

    @Test func emptyHunkReturnsZero() {
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 10,
                frames: [:],
                lineCount: 0,
                fallbackHeight: fallback
            ) == 0
        )
    }

    @Test func withoutFramesUsesUniformFallbackFromTop() {
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 0,
                frames: [:],
                lineCount: 5,
                fallbackHeight: fallback
            ) == 0
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 19.9,
                frames: [:],
                lineCount: 5,
                fallbackHeight: fallback
            ) == 0
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 20,
                frames: [:],
                lineCount: 5,
                fallbackHeight: fallback
            ) == 1
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 99,
                frames: [:],
                lineCount: 5,
                fallbackHeight: fallback
            ) == 4
        )
    }

    @Test func hitsInsideAMeasuredFrameReturnThatRow() {
        let frames: [Int: DiffCodeRowFrame] = [
            0: DiffCodeRowFrame(minY: 0, height: 40),
            1: DiffCodeRowFrame(minY: 40, height: 20),
            2: DiffCodeRowFrame(minY: 60, height: 60),
        ]

        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 0,
                frames: frames,
                lineCount: 3,
                fallbackHeight: fallback
            ) == 0
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 39.9,
                frames: frames,
                lineCount: 3,
                fallbackHeight: fallback
            ) == 0
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 40,
                frames: frames,
                lineCount: 3,
                fallbackHeight: fallback
            ) == 1
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 100,
                frames: frames,
                lineCount: 3,
                fallbackHeight: fallback
            ) == 2
        )
    }

    @Test func wrappedTallRowIsNotConfusedWithTheNextUniformRow() {
        // Old bug: y / singleLineHeight would map the second visual band of a wrap
        // onto the next logical row.
        let frames: [Int: DiffCodeRowFrame] = [
            0: DiffCodeRowFrame(minY: 0, height: 40),
            1: DiffCodeRowFrame(minY: 40, height: 20),
        ]

        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 25,
                frames: frames,
                lineCount: 2,
                fallbackHeight: fallback
            ) == 0
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 45,
                frames: frames,
                lineCount: 2,
                fallbackHeight: fallback
            ) == 1
        )
    }

    @Test func yPastLastMeasuredFrameStepsByFallback() {
        let frames: [Int: DiffCodeRowFrame] = [
            0: DiffCodeRowFrame(minY: 0, height: 40),
            1: DiffCodeRowFrame(minY: 40, height: 20),
        ]

        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 60,
                frames: frames,
                lineCount: 5,
                fallbackHeight: fallback
            ) == 2
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 80,
                frames: frames,
                lineCount: 5,
                fallbackHeight: fallback
            ) == 3
        )
    }

    @Test func yAboveFirstMeasuredFrameStepsBackwardByFallback() {
        let frames: [Int: DiffCodeRowFrame] = [
            3: DiffCodeRowFrame(minY: 100, height: 20),
        ]

        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 90,
                frames: frames,
                lineCount: 5,
                fallbackHeight: fallback
            ) == 2
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 70,
                frames: frames,
                lineCount: 5,
                fallbackHeight: fallback
            ) == 1
        )
    }

    @Test func holeBetweenMeasuredFramesStepsFromTheLowerNeighbour() {
        let frames: [Int: DiffCodeRowFrame] = [
            0: DiffCodeRowFrame(minY: 0, height: 20),
            3: DiffCodeRowFrame(minY: 80, height: 20),
        ]

        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 30,
                frames: frames,
                lineCount: 4,
                fallbackHeight: fallback
            ) == 1
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 50,
                frames: frames,
                lineCount: 4,
                fallbackHeight: fallback
            ) == 2
        )
    }

    @Test func resultIsClampedToLineCount() {
        let frames: [Int: DiffCodeRowFrame] = [
            0: DiffCodeRowFrame(minY: 0, height: 20),
        ]

        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: 10_000,
                frames: frames,
                lineCount: 2,
                fallbackHeight: fallback
            ) == 1
        )
        #expect(
            DiffCodeSelectionHitTesting.rowIndex(
                atY: -40,
                frames: frames,
                lineCount: 2,
                fallbackHeight: fallback
            ) == 0
        )
    }
}
