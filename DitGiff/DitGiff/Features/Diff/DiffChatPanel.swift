import Combine
import SwiftUI

/// The conversation beside the diff. The agent answers with clues; the reader decides.
struct DiffChatPanel: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var model: DiffModel
    @State private var hasEntered = false

    var body: some View {
        DSVStack(spacing: nil) {
            DiffChatHeader { model.closeChat() }
            DiffChatMessageList(model: model)
            DiffChatFooter(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface1)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(width: DiffChatPanelMetric.hairline)
        }
        .offset(x: hasEntered ? 0 : DiffChatPanelMetric.entryOffset)
        .opacity(hasEntered ? 1 : 0)
        .onAppear {
            withAnimation(DSMotion.collapse.animation(reduceMotion: reduceMotion)) {
                hasEntered = true
            }
        }
        .onExitCommand {
            model.closeChat()
        }
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
private enum DiffChatPanelMetric {
    static let hairline: CGFloat = 1
    static let entryOffset: CGFloat = 24
    static let closePadding: CGFloat = 4

    static let bubbleMaxWidthFraction: CGFloat = 0.86
    static let bubbleRadius: CGFloat = 12
    static let chipSize: CGFloat = 10
    static let chipVerticalPadding: CGFloat = 2

    static let thinkInterval: TimeInterval = 0.130
    static let thinkGlyphWidth: CGFloat = 9

    static let composerMinHeight: CGFloat = 52
    static let composerMaxHeight: CGFloat = 120
    static let selectVerticalPadding: CGFloat = 2
    static let selectControlHeight: CGFloat = 22
}

// MARK: - Header

private struct DiffChatHeader: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHoveringClose = false

    let close: () -> Void

    var body: some View {
        DSHStack(spacing: .s8) {
            Text("Chat")
                .dsText(.panelTitle)
                .foregroundStyle(palette.textPrimary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                DiffCloseIcon()
                    .foregroundStyle(
                        isHoveringClose ? palette.textPrimary.color : palette.textTertiary.color
                    )
                    .padding(DiffChatPanelMetric.closePadding)
                    .background {
                        RoundedRectangle(cornerRadius: DSRadius.sm.points, style: .continuous)
                            .fill(isHoveringClose ? palette.surface3.color : Color.clear)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .accessibilityLabel("Close chat")
        }
        .dsPadding(.top, .s8)
        .dsPadding(.bottom, .s8)
        .dsPadding(.trailing, .s8)
        .dsPadding(.leading, .s12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(height: DiffChatPanelMetric.hairline)
        }
    }
}

// MARK: - Thread

private struct DiffChatMessageList: View {
    let model: DiffModel
    @State private var thinkStep = 0

    private var messages: [DiffChatMessage] {
        model.thread?.messages ?? []
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                DSVStack(alignment: .leading, spacing: .s12) {
                    ForEach(messages) { message in
                        DiffChatBubble(message: message)
                            .id(message.id)
                    }
                    if model.isThinking {
                        DiffChatThinkingBubble(
                            glyph: model.thinkingIndicator.glyph(step: thinkStep),
                            word: model.thinkingIndicator.word(step: thinkStep)
                        )
                        .id("thinking")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.vertical, .s16)
                .dsPadding(.horizontal, .s12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: messages.count) { _, _ in
                scrollToEnd(proxy: proxy)
            }
            .onChange(of: model.isThinking) { _, isThinking in
                if isThinking {
                    thinkStep = 0
                }
                scrollToEnd(proxy: proxy)
            }
        }
        .onReceive(
            Timer.publish(
                every: DiffChatPanelMetric.thinkInterval,
                on: .main,
                in: .common
            ).autoconnect()
        ) { _ in
            guard model.isThinking else { return }
            thinkStep += 1
        }
    }

    private func scrollToEnd(proxy: ScrollViewProxy) {
        if model.isThinking {
            withAnimation(DSMotion.collapse.animation) {
                proxy.scrollTo("thinking", anchor: .bottom)
            }
            return
        }
        guard let lastID = messages.last?.id else { return }
        withAnimation(DSMotion.collapse.animation) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct DiffChatBubble: View {
    @Environment(\.dsPalette) private var palette

    let message: DiffChatMessage

    private var isAgent: Bool { message.role == .agent }

    var body: some View {
        DSVStack(
            alignment: isAgent ? .leading : .trailing,
            spacing: isAgent ? .s8 : .s4
        ) {
            if !isAgent, let location = message.location {
                DiffChatUserLocationChip(location: location)
            }
            bubble
        }
        .frame(maxWidth: .infinity, alignment: isAgent ? .leading : .trailing)
        .padding(.leading, isAgent ? DSSpace.s8.points : 0)
        .padding(.trailing, isAgent ? 0 : DSSpace.s8.points)
    }

    private var bubble: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            if isAgent, let location = message.location {
                DiffChatAgentLocationChip(location: location)
            }
            Text(message.text)
                .dsText(.body)
                .foregroundStyle(palette.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dsPadding(.vertical, .s8)
        .dsPadding(.horizontal, .s12)
        .frame(
            maxWidth: DiffChatPanelMetric.bubbleMaxWidthFraction * DiffLayout.chatWidth,
            alignment: .leading
        )
        .background {
            RoundedRectangle(
                cornerRadius: DiffChatPanelMetric.bubbleRadius,
                style: .continuous
            )
            .fill((isAgent ? palette.surface2 : palette.surface3).color)
        }
    }
}

private struct DiffChatAgentLocationChip: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let location: String

    var body: some View {
        DSHStack(spacing: .s4) {
            DiffLocationDocIcon()
            Text(location)
                .font(DSTextStyle.code.font(fixedSize: DiffChatPanelMetric.chipSize))
        }
        .foregroundStyle(
            isHovering ? palette.textPrimary.color : palette.textSecondary.color
        )
        .padding(.vertical, DiffChatPanelMetric.chipVerticalPadding)
        .dsPadding(.horizontal, .s8)
        .dsSurface(palette.surface3, radius: .sm)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Location \(location)")
    }
}

private struct DiffChatUserLocationChip: View {
    @Environment(\.dsPalette) private var palette

    let location: String

    var body: some View {
        Text(location)
            .font(DSTextStyle.code.font(fixedSize: DiffChatPanelMetric.chipSize))
            .foregroundStyle(palette.textSecondary.color)
            .padding(.vertical, DiffChatPanelMetric.chipVerticalPadding)
            .dsPadding(.horizontal, .s8)
            .background {
                Capsule(style: .continuous)
                    .fill(palette.surface2.color)
            }
    }
}

private struct DiffChatThinkingBubble: View {
    @Environment(\.dsPalette) private var palette

    let glyph: String
    let word: String

    var body: some View {
        DSHStack(spacing: .s8) {
            Text(glyph)
                .dsText(.code)
                .foregroundStyle(palette.diffAdd.color)
                .frame(width: DiffChatPanelMetric.thinkGlyphWidth, alignment: .center)
            Text("\(word)…")
                .dsText(.label)
                .foregroundStyle(palette.textSecondary.color)
        }
        .dsPadding(.vertical, .s8)
        .dsPadding(.horizontal, .s12)
        .background {
            RoundedRectangle(
                cornerRadius: DiffChatPanelMetric.bubbleRadius,
                style: .continuous
            )
            .fill(palette.surface2.color)
        }
        .dsPadding(.leading, .s8)
        .accessibilityLabel(word)
    }
}

// MARK: - Footer

private struct DiffChatFooter: View {
    @Environment(\.dsPalette) private var palette

    @Bindable var model: DiffModel
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            DiffChatComposer(
                text: $draft,
                isFocused: $isComposerFocused,
                send: send
            )
            DSHStack(spacing: .s8) {
                DiffChatModelPicker(selection: $model.chatModel)
                Spacer(minLength: 0)
                DiffChatReasoningPicker(selection: $model.reasoningEffort)
            }
        }
        .dsPadding(.all, .s8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.borderSubtle.color)
                .frame(height: DiffChatPanelMetric.hairline)
        }
    }

    private func send() {
        model.send(draft)
        draft = ""
    }
}

private struct DiffChatComposer: View {
    @Environment(\.dsPalette) private var palette

    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let send: () -> Void

    @State private var contentHeight = DiffChatPanelMetric.composerMinHeight

    private var height: CGFloat {
        min(
            max(contentHeight, DiffChatPanelMetric.composerMinHeight),
            DiffChatPanelMetric.composerMaxHeight
        )
    }

    var body: some View {
        TextEditor(text: $text)
            .dsText(.body)
            .foregroundStyle(palette.textPrimary.color)
            .focused(isFocused)
            .scrollContentBackground(.hidden)
            .dsPadding(.vertical, .s8)
            .dsPadding(.horizontal, .s12)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .dsSurface(palette.surface2, radius: .md)
            .dsBorder(palette.border, radius: .md)
            .dsFocusRing(isFocused.wrappedValue, radius: .md)
            .overlay(alignment: .topLeading) { placeholder }
            .background(alignment: .topLeading) { heightProbe }
            .onKeyPress(.return, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.shift) {
                    return .ignored
                }
                send()
                return .handled
            }
    }

    @ViewBuilder
    private var placeholder: some View {
        if text.isEmpty {
            Text("Ask about this diff…")
                .dsText(.body)
                .foregroundStyle(palette.textTertiary.color)
                .dsPadding(.vertical, .s8)
                .dsPadding(.horizontal, .s12)
                .allowsHitTesting(false)
        }
    }

    private var heightProbe: some View {
        Text(text.isEmpty ? " " : text)
            .dsText(.body)
            .dsPadding(.vertical, .s8)
            .dsPadding(.horizontal, .s12)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                contentHeight = $0
            }
    }
}

private struct DiffChatModelPicker: View {
    @Environment(\.dsPalette) private var palette
    @Binding var selection: DiffChatModelOption

    var body: some View {
        DSHStack(spacing: .s4) {
            Text("Model")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
            Picker("Model", selection: $selection) {
                ForEach(DiffChatModelOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(height: DiffChatPanelMetric.selectControlHeight)
        }
        .padding(.vertical, DiffChatPanelMetric.selectVerticalPadding)
        .dsPadding(.leading, .s8)
        .dsPadding(.trailing, .s4)
        .dsSurface(palette.surface2, radius: .sm)
        .dsBorder(palette.borderSubtle, radius: .sm)
    }
}

private struct DiffChatReasoningPicker: View {
    @Environment(\.dsPalette) private var palette
    @Binding var selection: DiffReasoningEffort

    var body: some View {
        DSHStack(spacing: .s4) {
            Text("Reasoning")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
            Picker("Reasoning", selection: $selection) {
                ForEach(DiffReasoningEffort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(height: DiffChatPanelMetric.selectControlHeight)
        }
        .padding(.vertical, DiffChatPanelMetric.selectVerticalPadding)
        .dsPadding(.leading, .s8)
        .dsPadding(.trailing, .s4)
        .dsSurface(palette.surface2, radius: .sm)
        .dsBorder(palette.borderSubtle, radius: .sm)
    }
}

// MARK: - Previews

#Preview("Chat panel — dark") {
    let model = DiffModel()
    model.openChat()
    return DiffChatPanel(model: model)
        .frame(width: DiffLayout.chatWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.dark)
}

#Preview("Chat panel — light") {
    let model = DiffModel()
    model.openChat()
    return DiffChatPanel(model: model)
        .frame(width: DiffLayout.chatWidth, height: DiffLayout.minimumHeight)
        .preferredColorScheme(.light)
}
