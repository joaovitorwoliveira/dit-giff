import SwiftUI

/// Pick a repository, pick two branches, optionally say what the change is for.
/// Static prototype: sample data, no git, no file dialogs, no drag and drop.
struct WelcomeView: View {
    @Environment(\.dsPalette) private var palette
    @State private var model: WelcomeModel

    init() {
        _model = State(initialValue: WelcomeModel())
    }

    init(model: WelcomeModel) {
        _model = State(initialValue: model)
    }

    // The prototype's card carries a border, a shadow and its own traffic lights because
    // there it stands in for the window. Here the window is real, so the content sits
    // straight on it.
    var body: some View {
        DSVStack(alignment: .leading, spacing: .s16) {
            WelcomeHeader()
            if model.selectedRepository == nil {
                WelcomeRepositoryPicker(model: model)
            } else {
                WelcomeReviewSetup(model: model)
            }
        }
        .frame(width: WelcomeMetric.contentWidth)
        .dsPadding(.all, .s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface1)
    }
}

// MARK: - Metrics

/// The values the design system's closed scales do not spell. Nothing else in this file
/// may hold a raw number.
private enum WelcomeMetric {
    static let contentWidth: CGFloat = 460
    static let hairline: CGFloat = 1

    /// These three mirror the prototype, which applies a type token and then overrides
    /// only its size inline: `panel-title` at 15, `code` at 10 and at 11.
    static let titleSize: CGFloat = 15
    static let identifierSize: CGFloat = 10
    static let changeSummarySize: CGFloat = 11

    /// `tracking` is absolute in SwiftUI, so the prototype's 0.06em is resolved here.
    static let sectionLabelTracking = DSTextStyle.label.size * 0.06

    static let rowSymbolSize: CGFloat = 16
    static let basePickerWidth: CGFloat = 120
    static let goalEditorMaxHeight: CGFloat = 180
    static let goalEditorMinHeight = DSTextStyle.body.leading * 2

    /// Off the spacing scale, but it is what lands the button on the 28pt row height.
    static let primaryButtonVerticalPadding: CGFloat = 6

    static let disabledOpacity = 0.5
}

// MARK: - Chrome

private struct WelcomeHeader: View {
    @Environment(\.dsPalette) private var palette

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            Text("Dit Giff")
                .font(DSTextStyle.panelTitle.font(fixedSize: WelcomeMetric.titleSize))
                .foregroundStyle(palette.textPrimary.color)
            Text("Read the change before you open the MR.")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
        }
    }
}

private struct WelcomeSectionLabel: View {
    @Environment(\.dsPalette) private var palette

    let title: String

    var body: some View {
        Text(title.uppercased())
            .dsText(.label)
            .tracking(WelcomeMetric.sectionLabelTracking)
            .foregroundStyle(palette.textTertiary.color)
    }
}

/// The prototype draws a custom folder glyph; SF Symbols is the sanctioned substitute.
private struct WelcomeFolderSymbol: View {
    @Environment(\.dsPalette) private var palette

    var body: some View {
        Image(systemName: "folder")
            .font(.system(size: WelcomeMetric.rowSymbolSize))
            .foregroundStyle(palette.textTertiary.color)
    }
}

private struct WelcomeRepositoryIdentity: View {
    @Environment(\.dsPalette) private var palette

    let repository: WelcomeRepository

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            Text(repository.name)
                .dsText(.body)
                .foregroundStyle(palette.textPrimary.color)
            Text(repository.path)
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - State A: choosing a repository

private struct WelcomeRepositoryPicker: View {
    @Environment(\.dsPalette) private var palette

    let model: WelcomeModel

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            WelcomeSectionLabel(title: "Recent repositories")
            recentList
            openRow
        }
    }

    private var recentList: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            ForEach(Array(WelcomeSampleData.repositories.enumerated()), id: \.element.id) { index, repository in
                if index > 0 {
                    Rectangle()
                        .fill(palette.borderSubtle.color)
                        .frame(height: WelcomeMetric.hairline)
                }
                WelcomeRecentRow(repository: repository) {
                    model.select(repository)
                }
            }
        }
        .dsSurface(palette.surface2, radius: .md)
        .dsClip(.md)
        .dsBorder(palette.borderSubtle, radius: .md)
    }

    private var openRow: some View {
        DSHStack(spacing: .s12) {
            WelcomeSecondaryButton(title: "Open repository…") {
                model.selectFirstRepository()
            }
            Text("or drop a folder here")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
        }
    }
}

private struct WelcomeRecentRow: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let repository: WelcomeRepository
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            DSHStack(spacing: .s12) {
                WelcomeFolderSymbol()
                WelcomeRepositoryIdentity(repository: repository)
                Text(repository.currentBranch)
                    .font(DSTextStyle.code.font(fixedSize: WelcomeMetric.identifierSize))
                    .foregroundStyle(palette.textTertiary.color)
            }
            .dsPadding(.vertical, .s8)
            .dsPadding(.horizontal, .s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(isHovering ? palette.surface3 : palette.surface2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct WelcomeSecondaryButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsText(.body)
                .foregroundStyle(palette.textPrimary.color)
                .dsPadding(.vertical, .s4)
                .dsPadding(.horizontal, .s12)
                .dsSurface(palette.surface3, radius: .sm)
                .dsBorder(isHovering ? palette.textTertiary : palette.border, radius: .sm)
        }
        .buttonStyle(.plain)
        .dsFocusable(radius: .sm)
        .onHover { isHovering = $0 }
    }
}

// MARK: - State B: setting up the review

private struct WelcomeReviewSetup: View {
    @Bindable var model: WelcomeModel

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s16) {
            if let repository = model.selectedRepository {
                WelcomeSelectedRepositoryRow(repository: repository) {
                    model.clearRepository()
                }
            }
            WelcomeBranchSection(model: model)
            WelcomeGoalSection(model: model)
        }
    }
}

private struct WelcomeSelectedRepositoryRow: View {
    @Environment(\.dsPalette) private var palette

    let repository: WelcomeRepository
    let change: () -> Void

    var body: some View {
        DSHStack(spacing: .s12) {
            WelcomeFolderSymbol()
            WelcomeRepositoryIdentity(repository: repository)
            Button(action: change) {
                // Links are underlined text; there is no accent hue to color them with.
                Text("Change")
                    .dsText(.label)
                    .underline()
                    .foregroundStyle(palette.textSecondary.color)
            }
            .buttonStyle(.plain)
        }
        .dsPadding(.vertical, .s8)
        .dsPadding(.horizontal, .s12)
        .dsSurface(palette.surface2, radius: .md)
        .dsBorder(palette.borderSubtle, radius: .md)
    }
}

private struct WelcomeBranchSection: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var model: WelcomeModel

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            WelcomeSectionLabel(title: "Branches")
            DSHStack(spacing: .s8) {
                comparePicker
                Text("→")
                    .dsText(.body)
                    .foregroundStyle(palette.textTertiary.color)
                basePicker
            }
            if model.compareBranch != nil {
                Text(model.changeSummary)
                    .font(DSTextStyle.code.font(fixedSize: WelcomeMetric.changeSummarySize))
                    .foregroundStyle(palette.textSecondary.color)
            }
        }
    }

    private var comparePicker: some View {
        WelcomeBranchMenu(
            label: "Compare branch",
            options: WelcomeSampleData.compareBranches,
            clearTitle: WelcomeSampleData.compareBranchPlaceholder,
            selection: model.compareBranch
        ) { model.compareBranch = $0 }
            .frame(maxWidth: .infinity)
    }

    private var basePicker: some View {
        WelcomeBranchMenu(
            label: "Base branch",
            options: WelcomeSampleData.baseBranches,
            clearTitle: nil,
            selection: model.baseBranch
        ) { branch in
            guard let branch else { return }
            model.baseBranch = branch
        }
        .frame(width: WelcomeMetric.basePickerWidth)
    }
}

/// A `Picker` would bring the system's own chrome and accent color with it, so the
/// control is a bare `Menu` wearing the design system's surface and border.
private struct WelcomeBranchMenu: View {
    @Environment(\.dsPalette) private var palette

    let label: String
    let options: [String]
    let clearTitle: String?
    let selection: String?
    let select: (String?) -> Void

    var body: some View {
        Menu {
            if let clearTitle {
                Button(clearTitle) { select(nil) }
            }
            ForEach(options, id: \.self) { option in
                Button(option) { select(option) }
            }
        } label: {
            menuLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(label)
        .dsFocusable(radius: .sm)
    }

    private var menuLabel: some View {
        DSHStack(spacing: .s8) {
            Text(selection ?? clearTitle ?? "")
                .dsText(.body)
                .foregroundStyle(
                    selection == nil ? palette.textTertiary.color : palette.textPrimary.color
                )
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
        }
        .dsPadding(.horizontal, .s8)
        .frame(height: DSDensity.rowHeight)
        .dsSurface(palette.surface2, radius: .sm)
        .dsBorder(palette.border, radius: .sm)
        .contentShape(Rectangle())
    }
}

// MARK: - Goal and spec

private struct WelcomeGoalSection: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var model: WelcomeModel
    @FocusState private var isGoalFocused: Bool

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            DSVStack(alignment: .leading, spacing: nil) {
                WelcomeGoalEditor(text: $model.goal, focus: $isGoalFocused)
                specRow
            }
            .dsSurface(palette.surface2, radius: .md)
            .dsClip(.md)
            .dsBorder(palette.border, radius: .md)
            // The ring wraps the whole field rather than only the editor: the editor is
            // the top half of one bordered box, and a ring across its middle reads as a bug.
            .dsFocusRing(isGoalFocused, radius: .md)
            WelcomeFooter(model: model)
        }
    }

    private var specRow: some View {
        DSHStack(spacing: .s8) {
            if let specName = model.attachedSpecName {
                WelcomeSpecChip(specName: specName) { model.removeSpec() }
            } else {
                WelcomeAttachSpecButton { model.attachSpec() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsPadding(.top, .s4)
        .dsPadding(.horizontal, .s8)
        .dsPadding(.bottom, .s8)
    }
}

private struct WelcomeGoalEditor: View {
    @Environment(\.dsPalette) private var palette
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    @State private var contentHeight = WelcomeMetric.goalEditorMinHeight

    private var height: CGFloat {
        min(max(contentHeight, WelcomeMetric.goalEditorMinHeight), WelcomeMetric.goalEditorMaxHeight)
    }

    var body: some View {
        TextEditor(text: $text)
            .dsText(.body)
            .foregroundStyle(palette.textPrimary.color)
            .focused(focus)
            .scrollContentBackground(.hidden)
            // `TextEditor` insets its text by a few points that SwiftUI does not expose,
            // so it is padded one step below the placeholder to line up with it.
            .dsPadding(.vertical, .s8)
            .dsPadding(.horizontal, .s8)
            .frame(height: height)
            .overlay(alignment: .topLeading) { placeholder }
            .background(alignment: .topLeading) { heightProbe }
    }

    /// `TextEditor` has no placeholder of its own.
    @ViewBuilder
    private var placeholder: some View {
        if text.isEmpty {
            Text("What should this change do? (optional)")
                .dsText(.body)
                .foregroundStyle(palette.textTertiary.color)
                .dsPadding(.vertical, .s8)
                .dsPadding(.horizontal, .s12)
                .allowsHitTesting(false)
        }
    }

    /// Nor an intrinsic height that tracks its content, so the same string is laid out
    /// invisibly to find out how tall the editor should be.
    private var heightProbe: some View {
        Text(text.isEmpty ? " " : text)
            .dsText(.body)
            .dsPadding(.vertical, .s8)
            .dsPadding(.horizontal, .s12)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }
}

private struct WelcomeAttachSpecButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let attach: () -> Void

    var body: some View {
        Button(action: attach) {
            DSHStack(spacing: .s4) {
                Image(systemName: "paperclip")
                Text("Attach a .md spec")
            }
            .dsText(.label)
            .foregroundStyle(isHovering ? palette.textPrimary.color : palette.textTertiary.color)
            .dsPadding(.all, .s4)
            .dsSurface(isHovering ? palette.surface3 : palette.surface2, radius: .sm)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct WelcomeSpecChip: View {
    @Environment(\.dsPalette) private var palette

    let specName: String
    let remove: () -> Void

    var body: some View {
        DSHStack(spacing: .s4) {
            Image(systemName: "doc")
            Text(specName)
                .font(.system(size: WelcomeMetric.identifierSize, design: .monospaced))
            WelcomeRemoveSpecButton(remove: remove)
        }
        .dsText(.label)
        .foregroundStyle(palette.textSecondary.color)
        .dsPadding(.vertical, .s4)
        .dsPadding(.leading, .s8)
        .dsPadding(.trailing, .s4)
        .dsSurface(palette.surface3, radius: .sm)
    }
}

private struct WelcomeRemoveSpecButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            Image(systemName: "xmark")
                .dsText(.label)
                .foregroundStyle(isHovering ? palette.textPrimary.color : palette.textTertiary.color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove attached spec")
        .onHover { isHovering = $0 }
    }
}

// MARK: - Footer

private struct WelcomeFooter: View {
    @Environment(\.dsPalette) private var palette

    let model: WelcomeModel

    var body: some View {
        DSHStack(spacing: .s12) {
            Text("One sentence — or a spec file — makes the hints sharper. Never required.")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            WelcomePrimaryButton(title: "Open diff", isEnabled: model.canOpenDiff) {
                // The diff screen does not exist yet, so opening it does nothing.
            }
        }
    }
}

private struct WelcomePrimaryButton: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dsText(.panelTitle)
                .foregroundStyle(palette.textPrimary.color)
                .fixedSize()
                .padding(.vertical, WelcomeMetric.primaryButtonVerticalPadding)
                .dsPadding(.horizontal, .s16)
                .dsSurface(palette.surface3, radius: .sm)
                .dsBorder(isHovering ? palette.textTertiary : palette.border, radius: .sm)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .dsFocusable(radius: .sm)
        .opacity(isEnabled ? 1 : WelcomeMetric.disabledOpacity)
        .onHover { isHovering = isEnabled && $0 }
    }
}

// MARK: - Previews

@MainActor
private func welcomeModelWithRepositorySelected() -> WelcomeModel {
    let model = WelcomeModel()
    model.selectFirstRepository()
    return model
}

#Preview("No repository — dark") {
    WelcomeView()
        .preferredColorScheme(.dark)
}

#Preview("No repository — light") {
    WelcomeView()
        .preferredColorScheme(.light)
}

#Preview("Repository selected — dark") {
    WelcomeView(model: welcomeModelWithRepositorySelected())
        .preferredColorScheme(.dark)
}

#Preview("Repository selected — light") {
    WelcomeView(model: welcomeModelWithRepositorySelected())
        .preferredColorScheme(.light)
}
