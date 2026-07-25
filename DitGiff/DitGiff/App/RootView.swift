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
            // The Welcome screen keeps its own model, so going back starts the setup
            // over — repository and branches included, the way the prototype does it.
            WelcomeView { appModel.openDiff() }
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
    let model = AppModel()
    model.openDiff()
    return model
}
