import SwiftUI

@main
struct DitGiffApp: App {
    // The Welcome screen fits in far less, but the window outlives the screen: opening
    // the diff must not force a resize to see the change map, the code and the chat.
    private static let minimumWindowWidth = DiffLayout.minimumWidth
    private static let minimumWindowHeight = DiffLayout.minimumHeight

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(
                    minWidth: Self.minimumWindowWidth,
                    minHeight: Self.minimumWindowHeight
                )
        }
        // The diff's top bar is the window's chrome row: the content runs under a
        // transparent title bar so the real traffic lights sit inside it, which is where
        // the prototype drew them.
        .windowStyle(.hiddenTitleBar)
    }
}
