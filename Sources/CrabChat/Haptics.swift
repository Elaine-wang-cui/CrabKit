import UIKit

/// A light tap for copy, send, and the crab.
enum Haptics {
    static func soft(_ intensity: CGFloat = 0.55) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
    }

    static func copied() { soft(0.5) }
}
