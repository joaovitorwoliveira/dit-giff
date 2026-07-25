import SwiftUI

/// Five type roles, no more. Values from `docs/product/DESIGN-SYSTEM.md`.
enum DSTextStyle: CaseIterable {
    case panelTitle
    case body
    case label
    case code
    case lineNumber

    var size: CGFloat {
        switch self {
        case .panelTitle: 13
        case .body: 13
        case .label: 11
        case .code: 12
        case .lineNumber: 11
        }
    }

    var leading: CGFloat {
        switch self {
        case .panelTitle: 18
        case .body: 18
        case .label: 15
        case .code: 18
        case .lineNumber: 18
        }
    }

    var weight: Font.Weight {
        switch self {
        case .panelTitle: .semibold
        case .body: .regular
        case .label: .medium
        case .code: .regular
        case .lineNumber: .regular
        }
    }

    var isMonospaced: Bool {
        switch self {
        case .code, .lineNumber: true
        case .panelTitle, .body, .label: false
        }
    }

    var font: Font { font(fixedSize: size) }

    /// For the few places where the design keeps a token's face and weight but overrides
    /// its size. `fixedSize` because type that scales with Dynamic Type would drift out of
    /// the diff gutter.
    func font(fixedSize: CGFloat) -> Font {
        guard isMonospaced else { return .system(size: fixedSize, weight: weight) }
        guard DSCodeFont.isAvailable else {
            return .system(size: fixedSize, weight: weight, design: .monospaced)
        }
        return .custom(DSCodeFont.faceName(for: weight), fixedSize: fixedSize)
    }

    // SwiftUI has no line-height: `lineSpacing` is the gap added on top of the font's
    // natural leading, about 1.2x the size. The code view will need exact metrics from
    // AppKit later; for interface text this is invisible.
    var lineSpacing: CGFloat {
        max(0, leading - size * 1.2)
    }
}

enum DSOpacity {
    static let read: Double = 0.45
}
