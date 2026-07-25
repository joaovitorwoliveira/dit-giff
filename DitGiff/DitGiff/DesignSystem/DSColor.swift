import SwiftUI

/// Source of truth: the revision 2 palette shipped in `docs/design-handoff/Dit Giff v2.dc.html`,
/// which supersedes the older values in `docs/product/DESIGN-SYSTEM.md`.
/// Light now derives from Solarized Light (base3 #FDF6E3, base2 #EEE8D5, base00 #657B83,
/// base01 #586E75, base1 #93A1A1 and accents); dark still comes from v2.

// Tokens are components rather than `SwiftUI.Color` because a `Color` cannot be
// compared or have another token derived from it.
struct DSColorValue: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    func withOpacity(_ value: Double) -> DSColorValue {
        DSColorValue(red: red, green: green, blue: blue, opacity: value)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

/// Popovers only. Elevation everywhere else comes from the surface scale.
struct DSShadow: Equatable, Sendable {
    let color: DSColorValue
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

/// Diff fills are the diff colors at low alpha. Add and remove carry slightly
/// different values so the two sides read as equally strong.
struct DSDiffFill: Sendable {
    let addLine: Double
    let delLine: Double
    let addWord: Double
    let delWord: Double
}

/// Syntax highlighting for the diff. The only place in the interface where hues
/// beyond the diff pair are allowed.
struct DSSyntaxPalette: Sendable {
    let keyword: DSColorValue
    let type: DSColorValue
    let string: DSColorValue
    let number: DSColorValue
    let comment: DSColorValue
    let function: DSColorValue
    let punctuation: DSColorValue
}

struct DSPalette: Sendable {
    let surface0: DSColorValue
    let surface1: DSColorValue
    let surface2: DSColorValue
    let surface3: DSColorValue
    let borderSubtle: DSColorValue
    let border: DSColorValue
    let textPrimary: DSColorValue
    let textSecondary: DSColorValue
    let textTertiary: DSColorValue
    /// Notices and recoverable failures. Rose, not the coral of `diffDel` — error and
    /// deletion must stay distinguishable when they share a screen.
    let textError: DSColorValue
    let diffAdd: DSColorValue
    let diffDel: DSColorValue
    let diffFill: DSDiffFill
    let focusRingOpacity: Double
    let syntax: DSSyntaxPalette
    let popoverShadow: DSShadow

    private static let textSelectionOpacity = 0.30

    // Derived from the two diff colors, never their own hexes, so a second green or a
    // second red cannot enter the system by accident.
    var diffAddBackground: DSColorValue { diffAdd.withOpacity(diffFill.addLine) }
    var diffDelBackground: DSColorValue { diffDel.withOpacity(diffFill.delLine) }
    var diffAddWord: DSColorValue { diffAdd.withOpacity(diffFill.addWord) }
    var diffDelWord: DSColorValue { diffDel.withOpacity(diffFill.delWord) }

    // Revision 2 moved the focus ring off the diff color onto muted text; selection
    // still borrows diffAdd.
    var focusRing: DSColorValue { textSecondary.withOpacity(focusRingOpacity) }
    var textSelection: DSColorValue { diffAdd.withOpacity(Self.textSelectionOpacity) }
    var selectionRule: DSColorValue { diffAdd }
    var selectionBackground: DSColorValue { surface3 }

    static let dark = DSPalette(
        surface0: DSColorValue(hex: 0x0A0B0D),
        surface1: DSColorValue(hex: 0x0F1113),
        surface2: DSColorValue(hex: 0x14161A),
        surface3: DSColorValue(hex: 0x1B1E23),
        borderSubtle: DSColorValue(hex: 0x1F2227),
        border: DSColorValue(hex: 0x2B2F36),
        textPrimary: DSColorValue(hex: 0xE7E9EC),
        textSecondary: DSColorValue(hex: 0x9BA1A9),
        textTertiary: DSColorValue(hex: 0x666C75),
        textError: DSColorValue(hex: 0xC97B88),
        diffAdd: DSColorValue(hex: 0x3DDC5E),
        diffDel: DSColorValue(hex: 0xFF5744),
        diffFill: DSDiffFill(addLine: 0.17, delLine: 0.17, addWord: 0.38, delWord: 0.38),
        focusRingOpacity: 0.40,
        syntax: DSSyntaxPalette(
            keyword: DSColorValue(hex: 0xC594E0),
            type: DSColorValue(hex: 0x5FD4C4),
            string: DSColorValue(hex: 0xE0B486),
            number: DSColorValue(hex: 0xE5936B),
            comment: DSColorValue(hex: 0x5F6B78),
            function: DSColorValue(hex: 0x7FA6FF),
            punctuation: DSColorValue(hex: 0x8A93A0)
        ),
        // CSS blur radius is about twice SwiftUI's, so the token's 24px is 12 here.
        popoverShadow: DSShadow(color: DSColorValue(hex: 0x000000, opacity: 0.44), radius: 12, x: 0, y: 8)
    )

    static let light = DSPalette(
        surface0: DSColorValue(hex: 0xFDF6E3),
        surface1: DSColorValue(hex: 0xF5EFDC),
        surface2: DSColorValue(hex: 0xFAF4E1),
        surface3: DSColorValue(hex: 0xEEE8D5),
        borderSubtle: DSColorValue(hex: 0xE3DCC6),
        border: DSColorValue(hex: 0xCFC7AE),
        textPrimary: DSColorValue(hex: 0x586E75),
        textSecondary: DSColorValue(hex: 0x657B83),
        textTertiary: DSColorValue(hex: 0x93A1A1),
        textError: DSColorValue(hex: 0x9A4554),
        diffAdd: DSColorValue(hex: 0x189938),
        diffDel: DSColorValue(hex: 0xE0230E),
        diffFill: DSDiffFill(addLine: 0.15, delLine: 0.14, addWord: 0.30, delWord: 0.28),
        focusRingOpacity: 0.32,
        syntax: DSSyntaxPalette(
            keyword: DSColorValue(hex: 0x859900),
            type: DSColorValue(hex: 0xB58900),
            string: DSColorValue(hex: 0x2AA198),
            number: DSColorValue(hex: 0xD33682),
            comment: DSColorValue(hex: 0x93A1A1),
            function: DSColorValue(hex: 0x268BD2),
            punctuation: DSColorValue(hex: 0x657B83)
        ),
        popoverShadow: DSShadow(color: DSColorValue(hex: 0x101815, opacity: 0.12), radius: 12, x: 0, y: 8)
    )

    static func resolved(for scheme: ColorScheme) -> DSPalette {
        scheme == .light ? .light : .dark
    }
}

extension EnvironmentValues {
    // Computed from the color scheme rather than injected, so it follows the OS on its
    // own and still obeys `.preferredColorScheme` when a mode gets pinned.
    var dsPalette: DSPalette { DSPalette.resolved(for: colorScheme) }
}
