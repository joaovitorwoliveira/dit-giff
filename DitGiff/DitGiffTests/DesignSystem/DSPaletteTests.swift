import Testing

@testable import DitGiff

struct DSPaletteTests {
    @Test @MainActor func textErrorIsDistinctFromDiffDeleteInBothThemes() {
        #expect(DSPalette.dark.textError != DSPalette.dark.diffDel)
        #expect(DSPalette.light.textError != DSPalette.light.diffDel)

        // Dusty rose / wine — not the coral of deleted lines.
        #expect(DSPalette.dark.textError == DSColorValue(hex: 0xC97B88))
        #expect(DSPalette.light.textError == DSColorValue(hex: 0x9A4554))
        #expect(DSPalette.dark.diffDel == DSColorValue(hex: 0xFF5744))
        #expect(DSPalette.light.diffDel == DSColorValue(hex: 0xE0230E))
    }
}
