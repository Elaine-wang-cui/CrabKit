import SwiftUI
import UIKit

/// Optional background image kept in memory for this screen only.
@MainActor @Observable
final class CustomBackground {
    static let shared = CustomBackground()
    private(set) var image: UIImage?

    func set(_ data: Data) {
        image = UIImage(data: data)
    }

    func clear() { image = nil }
}

/// The layer behind the transcript: an optional image, a mood wash, or a flat color.
struct ChatBackdrop: View {
    var specks = 38
    @Environment(ChatChrome.self) private var settings

    var body: some View {
        ZStack {
            if settings.palette == .custom, let img = CustomBackground.shared.image {
                Theme.background
                GeometryReader { g in
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.size.width, height: g.size.height)
                        .clipped()
                        .blur(radius: settings.bgBlur, opaque: true)
                }
                Theme.background.opacity(settings.bgDim)
            } else if settings.moodWallpaper && settings.palette != .official {
                MoodWallpaper()
            } else {
                Theme.background
            }
            if settings.palette == .nightsea {
                NightSpecks(count: specks)
            }
        }
        .allowsHitTesting(false)
    }
}
