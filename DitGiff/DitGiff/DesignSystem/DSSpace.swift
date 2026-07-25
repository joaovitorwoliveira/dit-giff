import CoreGraphics

/// The spacing scale, closed on purpose. An enum has no `DSSpace(20)`, so a value
/// outside the scale cannot be spelled.
enum DSSpace: CGFloat, CaseIterable {
    case s4 = 4
    case s8 = 8
    case s12 = 12
    case s16 = 16
    case s24 = 24
    case s32 = 32
    case s48 = 48

    var points: CGFloat { rawValue }
}

/// sm: badges and chips. md: hunk blocks and cards. lg: popovers and floating panels.
enum DSRadius: CGFloat, CaseIterable {
    case sm = 6
    case md = 10
    case lg = 14

    var points: CGFloat { rawValue }
}

enum DSDensity {
    static let rowHeight: CGFloat = 28
    static let panelPadding: CGFloat = 12
    static let diffGutterWidth: CGFloat = 44
}
