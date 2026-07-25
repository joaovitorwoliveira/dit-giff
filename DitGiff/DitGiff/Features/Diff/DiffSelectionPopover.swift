import SwiftUI

/// The floating ask that appears once a run of lines is selected. It is a clue about what
/// to ask next — not a verdict about the selection.
struct DiffSelectionPopover: View {
    @Environment(\.dsPalette) private var palette

    @Bindable var model: DiffModel
    @State private var question = ""
    @FocusState private var isQuestionFocused: Bool

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            explainButton
            divider
            queryRow
            locationLine
        }
        .frame(width: DiffSelectionPopoverMetric.width)
        .dsSurface(palette.surface2, radius: .md)
        .dsBorder(palette.border, radius: .md)
        .dsClip(.md)
        .dsPopoverShadow()
    }

    private var explainButton: some View {
        Button {
            model.explainSelection()
        } label: {
            DSHStack(spacing: .s8) {
                DiffExplainSelectionIcon()
                Text("Explain selection")
                    .dsText(.body)
            }
            .foregroundStyle(palette.textPrimary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPadding(.vertical, .s8)
            .dsPadding(.horizontal, .s12)
            .contentShape(Rectangle())
        }
        .buttonStyle(DiffSelectionPopoverRowStyle())
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.borderSubtle.color)
            .frame(height: DiffSelectionPopoverMetric.hairline)
    }

    private var queryRow: some View {
        DSHStack(spacing: .s8) {
            TextField(
                text: $question,
                prompt: Text("Ask something specific…")
                    .foregroundStyle(palette.textTertiary.color)
            ) {
                Text("Ask something specific…")
            }
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(DSTextStyle.body.font(fixedSize: DiffSelectionPopoverMetric.fieldSize))
            .foregroundStyle(palette.textPrimary.color)
            .focused($isQuestionFocused)
            .focusEffectDisabled()
            .padding(.vertical, DiffSelectionPopoverMetric.fieldVerticalPadding)
            .dsPadding(.horizontal, .s8)
            .frame(maxWidth: .infinity)
            .dsSurface(palette.surface1, radius: .sm)
            .dsBorder(
                isQuestionFocused ? palette.diffAdd : palette.borderSubtle,
                radius: .sm
            )
            .onSubmit { sendQuestion() }

            DiffSelectionSendButton(isEnabled: true, action: sendQuestion)
        }
        .dsPadding(.all, .s8)
    }

    private var locationLine: some View {
        Text(model.selection?.location ?? "")
            .font(DSTextStyle.label.font(fixedSize: DiffSelectionPopoverMetric.locationSize))
            .foregroundStyle(palette.textTertiary.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsPadding(.horizontal, .s12)
            .dsPadding(.bottom, .s8)
    }

    private func sendQuestion() {
        model.askAboutSelection(question)
        question = ""
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
private enum DiffSelectionPopoverMetric {
    static let width: CGFloat = 280
    static let hairline: CGFloat = 1
    static let fieldSize: CGFloat = 13
    static let fieldVerticalPadding: CGFloat = 6
    static let sendPadding: CGFloat = 6
    static let locationSize: CGFloat = 11
}

// MARK: - Controls

private struct DiffSelectionSendButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DiffSendArrowIcon()
                .foregroundStyle(
                    isHovering ? palette.textPrimary.color : palette.textTertiary.color
                )
                .padding(DiffSelectionPopoverMetric.sendPadding)
                .background {
                    RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                        .fill(isHovering ? palette.surface3.color : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Send question")
    }
}

/// Full-width row that paints `surface3` on hover without fighting the popover's surface.
private struct DiffSelectionPopoverRowStyle: ButtonStyle {
    @Environment(\.dsPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        DiffSelectionPopoverRow(configuration: configuration, palette: palette)
    }
}

private struct DiffSelectionPopoverRow: View {
    @State private var isHovering = false

    let configuration: ButtonStyleConfiguration
    let palette: DSPalette

    var body: some View {
        configuration.label
            .background(
                (isHovering || configuration.isPressed)
                    ? palette.surface3.color
                    : Color.clear
            )
            .onHover { isHovering = $0 }
    }
}

// MARK: - Previews

#Preview("Selection popover — dark") {
    let model = DiffModel()
    model.selectLines(inHunkWithID: "h1", from: 0, through: 2)
    return DiffSelectionPopover(model: model)
        .dsPadding(.all, .s24)
        .dsSurface(DSPalette.dark.surface0)
        .preferredColorScheme(.dark)
}

#Preview("Selection popover — light") {
    let model = DiffModel()
    model.selectLines(inHunkWithID: "h1", from: 0, through: 2)
    return DiffSelectionPopover(model: model)
        .dsPadding(.all, .s24)
        .dsSurface(DSPalette.light.surface0)
        .preferredColorScheme(.light)
}
