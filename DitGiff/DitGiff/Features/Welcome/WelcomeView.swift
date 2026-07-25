import SwiftUI
import UniformTypeIdentifiers

/// Pick a repository, pick two branches, optionally say what the change is for.
/// Repositories, branches and change counts come from git; goal and spec stay mocked
/// until Slice 5.
struct WelcomeView: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var model: WelcomeModel
    private let openDiff: () -> Void

    init(model: WelcomeModel, openDiff: @escaping () -> Void) {
        self.model = model
        self.openDiff = openDiff
    }

    // The prototype's card carries a border, a shadow and its own traffic lights because
    // there it stands in for the window. Here the window is real, so the content sits
    // straight on it.
    var body: some View {
        DSVStack(alignment: .leading, spacing: .s16) {
            WelcomeHeader()
            if let banner = model.banner {
                WelcomeBannerView(banner: banner) {
                    model.dismissBanner()
                } action: {
                    model.performBannerAction()
                }
            }
            if model.selectedRepository == nil {
                WelcomeRepositoryPicker(model: model)
            } else {
                WelcomeReviewSetup(model: model, openDiff: openDiff)
            }
        }
        .frame(width: WelcomeMetric.contentWidth)
        .dsPadding(.all, .s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsSurface(palette.surface1)
        .opacity(model.isOpeningRepository ? WelcomeMetric.disabledOpacity : 1)
        .allowsHitTesting(!model.isOpeningRepository)
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

    let name: String
    let path: String
    var isEmphasized = true

    var body: some View {
        DSVStack(alignment: .leading, spacing: nil) {
            Text(name)
                .dsText(.body)
                .foregroundStyle(
                    isEmphasized ? palette.textPrimary.color : palette.textTertiary.color
                )
            Text(path)
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WelcomeBannerView: View {
    @Environment(\.dsPalette) private var palette

    let banner: WelcomeBanner
    let dismiss: () -> Void
    let action: () -> Void

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            DSHStack(alignment: .top, spacing: .s8) {
                Text(banner.message)
                    .dsText(.label)
                    .foregroundStyle(palette.textError.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .dsText(.label)
                        .foregroundStyle(palette.textTertiary.color)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            if banner.actionTitle != nil {
                Button(action: action) {
                    Text(banner.actionTitle ?? "")
                        .dsText(.label)
                        .underline()
                        .foregroundStyle(palette.textSecondary.color)
                }
                .buttonStyle(.plain)
            }
        }
        .dsPadding(.all, .s12)
        .dsSurface(palette.surface2, radius: .md)
        .dsBorder(palette.border, radius: .md)
    }
}

// MARK: - State A: choosing a repository

private struct WelcomeRepositoryPicker: View {
    @Environment(\.dsPalette) private var palette
    @Bindable var model: WelcomeModel

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s8) {
            WelcomeSectionLabel(title: "Recent repositories")
            recentList
            openRow
        }
    }

    @ViewBuilder
    private var recentList: some View {
        if model.recentRepositories.isEmpty {
            Text("No recent repositories yet. Open a folder to begin.")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.all, .s12)
                .dsSurface(palette.surface2, radius: .md)
                .dsClip(.md)
                .dsBorder(palette.borderSubtle, radius: .md)
        } else {
            DSVStack(alignment: .leading, spacing: nil) {
                ForEach(Array(model.recentRepositories.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.borderSubtle.color)
                            .frame(height: WelcomeMetric.hairline)
                    }
                    WelcomeRecentRow(entry: entry) {
                        model.selectRecent(entry)
                    }
                }
            }
            .dsSurface(palette.surface2, radius: .md)
            .dsClip(.md)
            .dsBorder(palette.borderSubtle, radius: .md)
        }
    }

    private var openRow: some View {
        DSHStack(spacing: .s12) {
            WelcomeSecondaryButton(title: "Open repository…") {
                model.chooseRepository()
            }
            Text("or drop a folder here")
                .dsText(.label)
                .foregroundStyle(
                    model.isDropTargeted ? palette.textPrimary.color : palette.textTertiary.color
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsPadding(.vertical, .s4)
                .dsPadding(.horizontal, .s8)
                .dsSurface(
                    model.isDropTargeted ? palette.surface3 : palette.surface2,
                    radius: .sm
                )
                .dsBorder(
                    model.isDropTargeted ? palette.textTertiary : palette.borderSubtle,
                    radius: .sm
                )
                .onDrop(of: [UTType.fileURL], isTargeted: dropTargetBinding) { providers in
                    handleDrop(providers)
                }
        }
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { model.isDropTargeted },
            set: { model.setDropTargeted($0) }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            Task { @MainActor in
                if let error {
                    model.reportDropFailure(
                        "Could not read that drop (\(error.localizedDescription)). Try “Open repository…” instead."
                    )
                    return
                }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let pathURL = item as? URL {
                    url = pathURL
                } else {
                    url = nil
                }
                guard let url else {
                    model.reportDropFailure(
                        "That drop was not a folder Dit Giff could open. Try “Open repository…” instead."
                    )
                    return
                }
                await model.openDroppedFolder(at: url)
            }
        }
        return true
    }
}

private struct WelcomeRecentRow: View {
    @Environment(\.dsPalette) private var palette
    @State private var isHovering = false

    let entry: WelcomeRecentEntry
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            DSHStack(spacing: .s12) {
                WelcomeFolderSymbol()
                WelcomeRepositoryIdentity(
                    name: entry.displayName,
                    path: entry.rootPath,
                    isEmphasized: entry.isAvailable
                )
                if entry.isAvailable, let headLabel = entry.headLabel {
                    Text(headLabel)
                        .font(DSTextStyle.code.font(fixedSize: WelcomeMetric.identifierSize))
                        .foregroundStyle(palette.textTertiary.color)
                        .lineLimit(1)
                }
                Text(entry.isAvailable ? "" : "Missing")
                    .font(DSTextStyle.code.font(fixedSize: WelcomeMetric.identifierSize))
                    .foregroundStyle(palette.textTertiary.color)
            }
            .dsPadding(.vertical, .s8)
            .dsPadding(.horizontal, .s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsSurface(isHovering ? palette.surface3 : palette.surface2)
            .opacity(entry.isAvailable ? 1 : WelcomeMetric.disabledOpacity)
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
    var isEnabled = true
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : WelcomeMetric.disabledOpacity)
        .dsFocusable(radius: .sm)
        .onHover { isHovering = isEnabled && $0 }
    }
}

// MARK: - State B: setting up the review

private struct WelcomeReviewSetup: View {
    @Bindable var model: WelcomeModel
    let openDiff: () -> Void

    var body: some View {
        DSVStack(alignment: .leading, spacing: .s16) {
            if let repository = model.selectedRepository {
                WelcomeSelectedRepositoryRow(
                    repository: repository,
                    isFetching: model.isFetching,
                    fetch: { model.fetch() },
                    change: { model.clearRepository() }
                )
            }
            WelcomeBranchSection(model: model)
            WelcomeGoalSection(model: model, openDiff: openDiff)
        }
    }
}

private struct WelcomeSelectedRepositoryRow: View {
    @Environment(\.dsPalette) private var palette

    let repository: GitRepository
    let isFetching: Bool
    let fetch: () -> Void
    let change: () -> Void

    var body: some View {
        DSHStack(spacing: .s12) {
            WelcomeFolderSymbol()
            WelcomeRepositoryIdentity(
                name: repository.displayName,
                path: repository.rootURL.path
            )
            WelcomeSecondaryButton(
                title: isFetching ? "Fetching…" : "Fetch",
                isEnabled: !isFetching,
                action: fetch
            )
            Button(action: change) {
                // Links are underlined text; there is no accent hue to color them with.
                Text("Change")
                    .dsText(.label)
                    .underline()
                    .foregroundStyle(palette.textSecondary.color)
            }
            .buttonStyle(.plain)
            .disabled(isFetching)
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
                    .foregroundStyle(
                        model.isCountingChanges
                            ? palette.textTertiary.color
                            : palette.textSecondary.color
                    )
            }
        }
    }

    private var comparePicker: some View {
        WelcomeBranchMenu(
            label: "Compare branch",
            options: model.branchDisplayNames,
            clearTitle: WelcomeSampleData.compareBranchPlaceholder,
            selection: model.compareBranch?.displayName
        ) { model.selectCompare(displayName: $0) }
            .frame(maxWidth: .infinity)
    }

    private var basePicker: some View {
        WelcomeBranchMenu(
            label: "Base branch",
            options: model.branchDisplayNames,
            clearTitle: nil,
            selection: model.baseBranch?.displayName
        ) { branch in
            model.selectBase(displayName: branch)
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
    let openDiff: () -> Void
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
            WelcomeFooter(model: model, openDiff: openDiff)
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
    let openDiff: () -> Void

    var body: some View {
        DSHStack(spacing: .s12) {
            Text("One sentence — or a spec file — makes the hints sharper. Never required.")
                .dsText(.label)
                .foregroundStyle(palette.textTertiary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The session is real; the diff screen still draws sample hunks until Slice 3.
            WelcomePrimaryButton(title: "Open diff", isEnabled: model.canOpenDiff, action: openDiff)
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
private func previewWelcomeModel() -> WelcomeModel {
    let runner = FakeCommandRunner()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("dit-giff-welcome-preview-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try! RecentRepositoriesStore(directoryURL: directory)
    return WelcomeModel(
        git: GitService(runner: runner),
        recentStore: store,
        directoryPicker: SystemDirectoryPicker()
    )
}

#Preview("No repository — dark") {
    WelcomeView(model: previewWelcomeModel()) {}
        .preferredColorScheme(.dark)
}

#Preview("No repository — light") {
    WelcomeView(model: previewWelcomeModel()) {}
        .preferredColorScheme(.light)
}
