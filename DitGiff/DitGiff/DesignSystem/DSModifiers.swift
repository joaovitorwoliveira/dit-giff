import SwiftUI

// SwiftUI's own `padding(_:)` and `VStack(spacing:)` take a bare `CGFloat`, which is
// where a closed scale leaks. Everything here takes a token instead.

extension View {
    func dsPadding(_ edges: Edge.Set = .all, _ space: DSSpace) -> some View {
        padding(edges, space.points)
    }

    func dsText(_ style: DSTextStyle) -> some View {
        font(style.font).lineSpacing(style.lineSpacing)
    }

    func dsClip(_ radius: DSRadius) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius.points, style: .continuous))
    }

    func dsSurface(_ value: DSColorValue, radius: DSRadius? = nil) -> some View {
        background {
            if let radius {
                RoundedRectangle(cornerRadius: radius.points, style: .continuous)
                    .fill(value.color)
            } else {
                Rectangle().fill(value.color)
            }
        }
    }

    func dsBorder(_ value: DSColorValue, radius: DSRadius, width: CGFloat = 1) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius.points, style: .continuous)
                .strokeBorder(value.color, lineWidth: width)
        }
    }

    func dsFocusRing(_ isFocused: Bool, radius: DSRadius) -> some View {
        modifier(DSFocusRingModifier(isFocused: isFocused, radius: radius))
    }

    /// For controls that are not focusable on their own. `TextEditor` and friends already
    /// are, so they take `dsFocusRing` with their own `@FocusState` instead.
    func dsFocusable(radius: DSRadius) -> some View {
        modifier(DSFocusableModifier(radius: radius))
    }

    func dsPopoverShadow() -> some View {
        modifier(DSPopoverShadowModifier())
    }
}

private struct DSFocusRingModifier: ViewModifier {
    @Environment(\.dsPalette) private var palette

    let isFocused: Bool
    let radius: DSRadius

    private static let ringWidth: CGFloat = 2
    private static let ringOffset: CGFloat = 1

    // The token is a CSS outline, which sits outside the control. Negative padding is how
    // an overlay grows past its content.
    private static let inset = -(ringOffset + ringWidth / 2)

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius.points - Self.inset, style: .continuous)
                .stroke(palette.focusRing.color, lineWidth: Self.ringWidth)
                .padding(Self.inset)
                .opacity(isFocused ? 1 : 0)
        }
    }
}

private struct DSFocusableModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    let radius: DSRadius

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            // AppKit draws its own ring in the system accent color on top of ours.
            .focusEffectDisabled()
            .dsFocusRing(isFocused, radius: radius)
    }
}

private struct DSPopoverShadowModifier: ViewModifier {
    @Environment(\.dsPalette) private var palette

    func body(content: Content) -> some View {
        let shadow = palette.popoverShadow
        return content.shadow(
            color: shadow.color.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }
}

/// `spacing: nil` means no gap. SwiftUI's default spacing is off the scale by
/// definition, so it is never used.
struct DSVStack<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: DSSpace?
    private let content: () -> Content

    init(
        alignment: HorizontalAlignment = .center,
        spacing: DSSpace? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: alignment, spacing: spacing?.points ?? 0, content: content)
    }
}

struct DSHStack<Content: View>: View {
    private let alignment: VerticalAlignment
    private let spacing: DSSpace?
    private let content: () -> Content

    init(
        alignment: VerticalAlignment = .center,
        spacing: DSSpace? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(alignment: alignment, spacing: spacing?.points ?? 0, content: content)
    }
}
