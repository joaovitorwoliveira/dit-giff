import SwiftUI

/// The only motions in the product. Nothing else animates.
enum DSMotion: CaseIterable {
    case collapse
    case read
    case jump
    case flash

    var duration: Double {
        switch self {
        case .collapse: 0.160
        case .read: 0.200
        case .jump: 0.240
        case .flash: 0.600
        }
    }

    var animation: Animation {
        switch self {
        case .collapse: .easeOut(duration: duration)
        case .read, .jump, .flash: .easeInOut(duration: duration)
        }
    }

    // `nil` is how SwiftUI spells "do not animate", which is what Reduce Motion asks for.
    func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
