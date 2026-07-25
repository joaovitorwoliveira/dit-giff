import SwiftUI

@main
struct DitGiffApp: App {
    private static let minimumWindowWidth: CGFloat = 560
    private static let minimumWindowHeight: CGFloat = 520

    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .frame(
                    minWidth: Self.minimumWindowWidth,
                    minHeight: Self.minimumWindowHeight
                )
        }
    }
}
