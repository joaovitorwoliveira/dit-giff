import AppKit
import SwiftUI

/// Preferred sidebar width: clamp, defaults key, and round-trip through `UserDefaults`.
/// The view binds via `AppStorage` on the same key; tests inject a suite.
enum DiffSidebarWidth {
    static let storageKey = "diff.sidebarWidth"
    static let defaultStorageValue = Double(DiffLayout.sidebarWidth)

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(max(width, DiffLayout.minimumSidebarWidth), DiffLayout.maximumSidebarWidth)
    }

    /// Preview width while the divider is dragged — clamp only, no persistence.
    static func previewWidth(committed: CGFloat, translation: CGFloat) -> CGFloat {
        clamped(committed + translation)
    }

    static func read(from defaults: UserDefaults) -> CGFloat {
        guard defaults.object(forKey: storageKey) != nil else {
            return DiffLayout.sidebarWidth
        }
        return clamped(CGFloat(defaults.double(forKey: storageKey)))
    }

    static func write(_ width: CGFloat, to defaults: UserDefaults) {
        defaults.set(Double(clamped(width)), forKey: storageKey)
    }
}

/// Drag handle between the change map and the reader.
///
/// During the drag the committed layout does not move. Only `previewWidth` updates so
/// the parent can paint a lightweight ghost line. Commit happens once on drag end
/// (and after each accessibility adjust).
struct DiffSidebarResizeDivider: View {
    @Environment(\.dsPalette) private var palette

    /// Width the sidebar is actually laid out at right now.
    let committedWidth: CGFloat
    /// In-gesture preview. `nil` when idle. Does not drive sidebar/reader layout.
    @Binding var previewWidth: CGFloat?
    /// Called once with the clamped width when a drag ends (or on accessibility adjust).
    var onCommit: (CGFloat) -> Void

    @State private var dragOriginWidth: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: DiffLayout.sidebarDividerWidth)
                .contentShape(Rectangle())
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(width: DiffSidebarResizeMetric.hairline)
        }
        .frame(maxHeight: .infinity)
        .pointerStyle(.columnResize)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(resizeDrag)
        .accessibilityLabel("Resize sidebar")
        .accessibilityAdjustableAction { direction in
            let step = DiffSidebarResizeMetric.accessibilityStep
            let next: CGFloat
            switch direction {
            case .increment:
                next = DiffSidebarWidth.clamped(committedWidth + step)
            case .decrement:
                next = DiffSidebarWidth.clamped(committedWidth - step)
            @unknown default:
                return
            }
            previewWidth = nil
            onCommit(next)
        }
    }

    private var resizeDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragOriginWidth == nil {
                    dragOriginWidth = committedWidth
                }
                guard let origin = dragOriginWidth else { return }
                previewWidth = DiffSidebarWidth.previewWidth(
                    committed: origin,
                    translation: value.translation.width
                )
            }
            .onEnded { _ in
                let next = previewWidth ?? committedWidth
                dragOriginWidth = nil
                previewWidth = nil
                onCommit(next)
            }
    }
}

// MARK: - Metrics

/// Values the design system's closed scales do not spell. The rule itself stays a hairline;
/// hit width lives on `DiffLayout.sidebarDividerWidth`.
private enum DiffSidebarResizeMetric {
    static let hairline: CGFloat = 1
    static let accessibilityStep: CGFloat = DSSpace.s16.points
}
