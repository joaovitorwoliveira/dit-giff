import CoreGraphics

/// In-file keyboard scroll for the reader. Distinct from left/right file jumps.
nonisolated enum DiffReaderScrollIntent: Equatable, Sendable {
    case pageDown
    case pageUp
    case lineDown
    case lineUp
}

/// Hardware keys that page or step the reader, expressed without SwiftUI types so the
/// mapping stays unit-testable. Left/right are intentionally absent — those jump files.
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

/// Single-letter reader shortcuts. Named so the handler never compares magic strings.
nonisolated enum DiffReaderLetterKey {
    static let nextUnreadFile = "n"
    static let toggleViewed = "v"
}

nonisolated enum DiffReaderLetterKeyMapping {
    enum Action: Equatable, Sendable {
        case nextUnreadFile
        case toggleViewed
    }

    static func action(for character: String) -> Action? {
        switch character {
        case DiffReaderLetterKey.nextUnreadFile: return .nextUnreadFile
        case DiffReaderLetterKey.toggleViewed: return .toggleViewed
        default: return nil
        }
    }
}

/// Converts a scroll intent into a content-offset target. The scroll view clamps past
/// the content bounds; this only keeps the offset from going negative.
nonisolated enum DiffReaderScrollPaging {
    /// How much of the visible viewport one page key covers. Slightly under 1.0 so a
    /// line of context survives each page — same idea as AppKit's page scroll overlap.
    static let pageViewportFraction: CGFloat = 0.9

    /// Arrow up/down step as a multiple of the code line height — a single line is too
    /// fine for reading a diff; five lines match one short glance.
    static let arrowLineStepCount: CGFloat = 5

    /// Hold-to-scroll uses the system key-repeat stream. Three lines per repeat keep
    /// continuous motion fast without losing place; bump this (not
    /// `arrowLineStepCount`) to retune holds.
    static let arrowLineRepeatStepCount: CGFloat = 3

    static func lineStepCount(isRepeat: Bool) -> CGFloat {
        isRepeat ? arrowLineRepeatStepCount : arrowLineStepCount
    }

    static func targetOffset(
        currentOffset: CGFloat,
        viewportHeight: CGFloat,
        lineHeight: CGFloat,
        intent: DiffReaderScrollIntent,
        isRepeat: Bool = false
    ) -> CGFloat {
        let delta: CGFloat
        switch intent {
        case .pageDown:
            delta = viewportHeight * pageViewportFraction
        case .pageUp:
            delta = -viewportHeight * pageViewportFraction
        case .lineDown:
            delta = lineHeight * lineStepCount(isRepeat: isRepeat)
        case .lineUp:
            delta = -lineHeight * lineStepCount(isRepeat: isRepeat)
        }
        return max(0, currentOffset + delta)
    }
}
