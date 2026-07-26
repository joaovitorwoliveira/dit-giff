import CoreGraphics

/// In-file keyboard scroll for the reader. Distinct from j / k file jumps.
nonisolated enum DiffReaderScrollIntent: Equatable, Sendable {
    case pageDown
    case pageUp
    case lineDown
    case lineUp
}

/// Hardware keys that page or step the reader, expressed without SwiftUI types so the
/// mapping stays unit-testable.
nonisolated struct DiffReaderScrollKeyEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case space
        case pageDown
        case pageUp
        case downArrow
        case upArrow
    }

    var kind: Kind
    /// Shift alone flips space into page-up. Any other modifier is rejected by the view
    /// before this mapping runs.
    var shift: Bool
}

nonisolated enum DiffReaderScrollKeyMapping {
    static func intent(for event: DiffReaderScrollKeyEvent) -> DiffReaderScrollIntent? {
        switch event.kind {
        case .space:
            return event.shift ? .pageUp : .pageDown
        case .pageDown:
            guard !event.shift else { return nil }
            return .pageDown
        case .pageUp:
            guard !event.shift else { return nil }
            return .pageUp
        case .downArrow:
            guard !event.shift else { return nil }
            return .lineDown
        case .upArrow:
            guard !event.shift else { return nil }
            return .lineUp
        }
    }
}

/// Converts a scroll intent into a content-offset target. The scroll view clamps past
/// the content bounds; this only keeps the offset from going negative.
nonisolated enum DiffReaderScrollPaging {
    /// How much of the visible viewport one page key covers. Slightly under 1.0 so a
    /// line of context survives each page — same idea as AppKit's page scroll overlap.
    static let pageViewportFraction: CGFloat = 0.9

    static func targetOffset(
        currentOffset: CGFloat,
        viewportHeight: CGFloat,
        lineHeight: CGFloat,
        intent: DiffReaderScrollIntent
    ) -> CGFloat {
        let delta: CGFloat
        switch intent {
        case .pageDown:
            delta = viewportHeight * pageViewportFraction
        case .pageUp:
            delta = -viewportHeight * pageViewportFraction
        case .lineDown:
            delta = lineHeight
        case .lineUp:
            delta = -lineHeight
        }
        return max(0, currentOffset + delta)
    }
}
