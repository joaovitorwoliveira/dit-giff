import CoreText
import OSLog
import SwiftUI

/// JetBrains Mono ships inside the bundle because no Mac has it. Registering the files
/// with the process is what makes `Font.custom` resolve them instead of quietly handing
/// back the system font.
enum DSCodeFont {
    private static let faces = [
        "JetBrainsMono-Regular",
        "JetBrainsMono-Medium",
        "JetBrainsMono-SemiBold",
    ]

    private static let log = Logger(subsystem: "DitGiff", category: "DesignSystem")

    /// A face that fails to register is a packaging bug, not a user-facing one: it is
    /// logged as an error and the type falls back to the system monospace.
    static let isAvailable: Bool = registerFaces()

    static func faceName(for weight: Font.Weight) -> String {
        switch weight {
        case .medium: "JetBrainsMono-Medium"
        case .semibold, .bold, .heavy, .black: "JetBrainsMono-SemiBold"
        default: "JetBrainsMono-Regular"
        }
    }

    private static func registerFaces() -> Bool {
        var didRegisterEveryFace = true

        for face in faces {
            guard let url = Bundle.main.url(forResource: face, withExtension: "ttf") else {
                log.error("\(face).ttf is not in the app bundle: check its target membership")
                didRegisterEveryFace = false
                continue
            }

            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
                let reason = error?.takeRetainedValue().localizedDescription ?? "unknown reason"
                log.error("could not register \(face): \(reason)")
                didRegisterEveryFace = false
                continue
            }
        }

        return didRegisterEveryFace
    }
}
