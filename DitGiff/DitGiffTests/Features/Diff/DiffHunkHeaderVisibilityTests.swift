import Testing

@testable import DitGiff

struct DiffHunkHeaderVisibilityTests {
    @Test func zeroHunksHideTheBand() {
        #expect(DiffHunkHeaderVisibility.showsHeader(hunkCount: 0) == false)
    }

    @Test func singleHunkHidesTheBand() {
        #expect(DiffHunkHeaderVisibility.showsHeader(hunkCount: 1) == false)
    }

    @Test func twoHunksShowTheBand() {
        #expect(DiffHunkHeaderVisibility.showsHeader(hunkCount: 2))
    }

    @Test func manyHunksShowTheBand() {
        #expect(DiffHunkHeaderVisibility.showsHeader(hunkCount: 5))
    }
}
