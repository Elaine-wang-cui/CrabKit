import UIKit

/// 轻一点的震动：碰一下就好，不要咔哒
enum CrabHaptics {
    @MainActor
    static func soft(_ intensity: CGFloat = 0.55) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
    }

    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
