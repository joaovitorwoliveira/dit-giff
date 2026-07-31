import CoreGraphics
import Testing

@testable import DitGiff

@MainActor
struct DiffReaderScrollGeometryStoreTests {
    @Test func identicalGeometryWithinToleranceDoesNotPublishChange() {
        let store = DiffReaderScrollGeometryStore()
        let first = store.update(
            offsetY: 100,
            viewportHeight: 600,
            viewportWidth: 871,
            contentHeight: 12_000
        )
        let second = store.update(
            offsetY: 100.2,
            viewportHeight: 600.3,
            viewportWidth: 871.4,
            contentHeight: 12_000.4
        )
        #expect(first)
        #expect(!second)
        #expect(store.offsetY == 100)
        #expect(store.viewportWidth == 871)
    }

    @Test func burstOfRepeatedGeometryEventsProducesOnePublication() {
        let store = DiffReaderScrollGeometryStore()
        var publications = 0
        for _ in 0..<100 {
            if store.update(
                offsetY: 500,
                viewportHeight: 871,
                viewportWidth: 871,
                contentHeight: 22_513
            ) {
                publications += 1
            }
        }
        #expect(publications == 1)
    }

    @Test func viewportWidthQuantizesToWholePoints() {
        let store = DiffReaderScrollGeometryStore()
        _ = store.update(
            offsetY: 0,
            viewportHeight: 600,
            viewportWidth: 871.9,
            contentHeight: 1_000
        )
        #expect(store.viewportWidth == 871)
        let republish = store.update(
            offsetY: 0,
            viewportHeight: 600,
            viewportWidth: 871.2,
            contentHeight: 1_000
        )
        #expect(!republish)
    }

    @Test func materialDimensionChangePublishesOnce() {
        let store = DiffReaderScrollGeometryStore()
        _ = store.update(
            offsetY: 0,
            viewportHeight: 600,
            viewportWidth: 871,
            contentHeight: 22_000
        )
        let changed = store.update(
            offsetY: 0,
            viewportHeight: 600,
            viewportWidth: 871,
            contentHeight: 33_000
        )
        #expect(changed)
        #expect(store.contentHeight == 33_000)
    }
}
