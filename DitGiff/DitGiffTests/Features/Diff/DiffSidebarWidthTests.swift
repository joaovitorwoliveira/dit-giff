import Foundation
import Testing

@testable import DitGiff

struct DiffSidebarWidthTests {
    // MARK: - Clamp

    @Test func clampingRaisesValuesBelowTheMinimum() {
        #expect(DiffSidebarWidth.clamped(0) == DiffLayout.minimumSidebarWidth)
        #expect(
            DiffSidebarWidth.clamped(DiffLayout.minimumSidebarWidth - 1)
                == DiffLayout.minimumSidebarWidth
        )
    }

    @Test func clampingLowersValuesAboveTheMaximum() {
        #expect(DiffSidebarWidth.clamped(10_000) == DiffLayout.maximumSidebarWidth)
        #expect(
            DiffSidebarWidth.clamped(DiffLayout.maximumSidebarWidth + 1)
                == DiffLayout.maximumSidebarWidth
        )
    }

    @Test func clampingLeavesValuesInsideTheRangeAlone() {
        #expect(DiffSidebarWidth.clamped(DiffLayout.sidebarWidth) == DiffLayout.sidebarWidth)
        let mid = (DiffLayout.minimumSidebarWidth + DiffLayout.maximumSidebarWidth) / 2
        #expect(DiffSidebarWidth.clamped(mid) == mid)
    }

    @Test func layoutBoundsAreNamedAndOrdered() {
        #expect(DiffLayout.minimumSidebarWidth < DiffLayout.sidebarWidth)
        #expect(DiffLayout.sidebarWidth < DiffLayout.maximumSidebarWidth)
        #expect(DiffLayout.maximumSidebarWidth == DiffLayout.minimumViewerWidth)
        #expect(DiffLayout.sidebarDividerWidth > 0)
        #expect(DiffLayout.sidebarDividerWidth < DiffLayout.minimumSidebarWidth)
    }

    // MARK: - Persistence

    @Test func preferredWidthRoundTripsThroughUserDefaults() throws {
        let suite = "ditgiff.tests.sidebar-width.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DiffSidebarWidth.write(360, to: defaults)

        #expect(DiffSidebarWidth.read(from: defaults) == 360)
    }

    @Test func missingPreferenceFallsBackToTheDefaultSidebarWidth() throws {
        let suite = "ditgiff.tests.sidebar-width.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(DiffSidebarWidth.read(from: defaults) == DiffLayout.sidebarWidth)
    }

    @Test func writingClampsBeforePersisting() throws {
        let suite = "ditgiff.tests.sidebar-width.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DiffSidebarWidth.write(50, to: defaults)
        #expect(DiffSidebarWidth.read(from: defaults) == DiffLayout.minimumSidebarWidth)

        DiffSidebarWidth.write(900, to: defaults)
        #expect(DiffSidebarWidth.read(from: defaults) == DiffLayout.maximumSidebarWidth)
    }

    @Test func readingClampsACorruptStoredValue() throws {
        let suite = "ditgiff.tests.sidebar-width.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(12.0, forKey: DiffSidebarWidth.storageKey)

        #expect(DiffSidebarWidth.read(from: defaults) == DiffLayout.minimumSidebarWidth)
    }

    // MARK: - Toggle preserves width

    @MainActor
    @Test func togglingSidebarVisibilityDoesNotChangePreferredWidth() throws {
        let suite = "ditgiff.tests.sidebar-width.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DiffSidebarWidth.write(360, to: defaults)
        let model = DiffModel()
        #expect(model.isSidebarOpen)

        model.toggleSidebar()
        #expect(model.isSidebarOpen == false)
        #expect(DiffSidebarWidth.read(from: defaults) == 360)

        model.toggleSidebar()
        #expect(model.isSidebarOpen)
        #expect(DiffSidebarWidth.read(from: defaults) == 360)
    }

    // MARK: - Ghost drag: preview ≠ layout; persist only on commit

    @Test func previewWidthFollowsTranslationAndClamps() {
        #expect(
            DiffSidebarWidth.previewWidth(committed: 280, translation: 40) == 320
        )
        #expect(
            DiffSidebarWidth.previewWidth(committed: 280, translation: -200)
                == DiffLayout.minimumSidebarWidth
        )
        #expect(
            DiffSidebarWidth.previewWidth(committed: 280, translation: 10_000)
                == DiffLayout.maximumSidebarWidth
        )
    }

    @Test func previewDuringDragDoesNotPersistUntilCommit() throws {
        let suite = "ditgiff.tests.sidebar-width.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DiffSidebarWidth.write(280, to: defaults)
        let committed = DiffSidebarWidth.read(from: defaults)

        // Gesture frames only compute a preview — applied/storage stay put.
        let previewA = DiffSidebarWidth.previewWidth(committed: committed, translation: 20)
        let previewB = DiffSidebarWidth.previewWidth(committed: committed, translation: 60)
        #expect(previewA == 300)
        #expect(previewB == 340)
        #expect(DiffSidebarWidth.read(from: defaults) == 280)

        // One write when the gesture ends.
        DiffSidebarWidth.write(previewB, to: defaults)
        #expect(DiffSidebarWidth.read(from: defaults) == 340)
    }

    @Test func commitStillClampsBeforePersisting() throws {
        let suite = "ditgiff.tests.sidebar-width.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        DiffSidebarWidth.write(280, to: defaults)
        let preview = DiffSidebarWidth.previewWidth(committed: 280, translation: 10_000)
        #expect(preview == DiffLayout.maximumSidebarWidth)

        DiffSidebarWidth.write(preview, to: defaults)
        #expect(DiffSidebarWidth.read(from: defaults) == DiffLayout.maximumSidebarWidth)
    }
}
