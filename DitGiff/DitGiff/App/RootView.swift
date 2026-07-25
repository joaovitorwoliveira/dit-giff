import SwiftUI

/// The window's one switch: Welcome or the diff, with the picked theme over both.
struct RootView: View {
    @State private var appModel: AppModel

    init() {
        _appModel = State(initialValue: AppModel())
    }

    init(appModel: AppModel) {
        _appModel = State(initialValue: appModel)
    }

    var body: some View {
        screen
            // `nil` hands the window back to the OS, which is the starting state.
            .preferredColorScheme(appModel.themeOverride)
    }

    @ViewBuilder
    private var screen: some View {
        switch appModel.route {
        case .welcome:
            WelcomeView(model: appModel.welcomeModel) {
                guard let session = appModel.welcomeModel.makeSession() else { return }
                appModel.openDiff(session)
            }
        case .diff:
            DiffView(
                model: appModel.diffModel,
                back: { appModel.returnToWelcome() },
                toggleTheme: { appModel.toggleTheme(from: $0) }
            )
        }
    }
}

#Preview("Welcome") {
    RootView()
}

#Preview("Diff") {
    RootView(appModel: diffRouteAppModel())
}

@MainActor
private func diffRouteAppModel() -> AppModel {
    // Sample DiffModel so the preview draws without git. `load` is a no-op on sample.
    let model = AppModel(
        welcomeModel: AppModel().welcomeModel,
        diffModel: DiffModel()
    )
    let repository = GitRepository(
        rootURL: URL(fileURLWithPath: "/tmp/preview", isDirectory: true),
        displayName: "preview",
        head: .branch("feature")
    )
    let base = GitBranch(name: "main", fullRef: "refs/heads/main", remote: nil)
    let compare = GitBranch(name: "feature", fullRef: "refs/heads/feature", remote: nil)
    model.openDiff(
        DiffSession(
            repository: repository,
            base: base,
            compare: compare,
            goal: "",
            attachedSpecName: nil
        )
    )
    return model
}
