import SwiftUI
import Testing

@testable import DitGiff

/// The font files are wired into the target by hand, and a resource that silently stops
/// being copied still builds. This is the test that notices.
@MainActor
struct CodeFontTests {
    @Test func everyBundledFaceRegisters() {
        #expect(DSCodeFont.isAvailable)
    }

    @Test func weightsMapToTheirOwnFace() {
        #expect(DSCodeFont.faceName(for: .regular) == "JetBrainsMono-Regular")
        #expect(DSCodeFont.faceName(for: .medium) == "JetBrainsMono-Medium")
        #expect(DSCodeFont.faceName(for: .semibold) == "JetBrainsMono-SemiBold")
    }
}
