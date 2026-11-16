import SwiftUI
import UIKit
import Observation

/// 配色：浅色深色一套、自定义背景（同一套颜色，背后换成自己的图）、夜海（深蓝，飘着小光点）
enum Palette: String, CaseIterable, Identifiable {
    case official, custom, nightsea
    var id: String { rawValue }
    var label: String {
        switch self {
        case .official: "Official"
        case .custom: "Custom background"
        case .nightsea: "Night sea"
        }
    }
}

/// 现在用哪套配色。界面读 Theme 的颜色时顺带订阅了它，换配色整个界面跟着刷
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    var palette: Palette = .official
}

enum Theme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// 自定义背景用浅色那套颜色，只换背后的图
    private static func pick(_ official: Color, _ night: Color) -> Color {
        ThemeStore.shared.palette == .nightsea ? night : official
    }

    static var background: Color { pick(Official.background, NightSea.background) }
    static var sidebar: Color { pick(Official.sidebar, NightSea.sidebar) }
    static var surface: Color { pick(Official.surface, NightSea.surface) }
    static var userBubble: Color { pick(Official.userBubble, NightSea.userBubble) }
    /// 气泡样式里助手那边的气泡
    static var assistantBubble: Color { pick(Official.assistantBubble, NightSea.assistantBubble) }
    static var selected: Color { pick(Official.selected, NightSea.selected) }
    static var codeBackground: Color { pick(Official.codeBackground, NightSea.codeBackground) }
    /// 代码块：浅色模式也用深底
    static var codeDark: Color { pick(Official.codeDark, NightSea.codeDark) }
    static var codeHeader: Color { pick(Official.codeHeader, NightSea.codeHeader) }
    /// 灰色的「思考中」条
    static var thinkingBar: Color { pick(Official.thinkingBar, NightSea.thinkingBar) }
    static var border: Color { pick(Official.border, NightSea.border) }
    static var textPrimary: Color { pick(Official.textPrimary, NightSea.textPrimary) }
    static var textSecondary: Color { pick(Official.textSecondary, NightSea.textSecondary) }
    /// 抽屉底部「新对话」那颗胶囊：浅色时黑底白字，深色时反过来
    static var pill: Color { pick(Official.pill, NightSea.pill) }
    static var pillText: Color { pick(Official.pillText, NightSea.pillText) }
    static var accent: Color { pick(Official.accent, NightSea.accent) }

    static func greetingFont(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    private enum Official {
        static let background = dynamic(0xF9F8F6, 0x262624)
        static let sidebar = dynamic(0xF3F2EE, 0x1F1E1C)
        static let surface = dynamic(0xFFFFFF, 0x302D29)
        static let userBubble = dynamic(0xFCF8F2, 0x2E2B27)
        static let assistantBubble = dynamic(0xFFFFFF, 0x33302B)
        static let selected = dynamic(0xE8E6E1, 0x3A3631)
        static let codeBackground = dynamic(0xF0ECE4, 0x1A1917)
        static let codeDark = dynamic(0x2B2926, 0x1B1A18)
        static let codeHeader = dynamic(0x34312E, 0x232120)
        static let thinkingBar = dynamic(0xEFEDE8, 0x33302C)
        static let border = dynamic(0xE5E3DE, 0x3D3934)
        static let textPrimary = dynamic(0x2A2622, 0xEDE8DF)
        static let textSecondary = dynamic(0x857D72, 0x9C958B)
        static let pill = dynamic(0x1F1D1A, 0xEDE8DF)
        static let pillText = dynamic(0xFFFFFF, 0x1F1D1A)
        static let accent = dynamic(0xE9704F, 0xE9704F)
    }


    /// 夜海只有深色
    private enum NightSea {
        static let background = dynamic(0x0E1A2B, 0x0E1A2B)
        static let sidebar = dynamic(0x0A1422, 0x0A1422)
        static let surface = dynamic(0x15243A, 0x15243A)
        static let userBubble = dynamic(0x142338, 0x142338)
        static let assistantBubble = dynamic(0x172840, 0x172840)
        static let selected = dynamic(0x1D3150, 0x1D3150)
        static let codeBackground = dynamic(0x0A1320, 0x0A1320)
        static let codeDark = dynamic(0x0A1320, 0x0A1320)
        static let codeHeader = dynamic(0x111D30, 0x111D30)
        static let thinkingBar = dynamic(0x182A44, 0x182A44)
        static let border = dynamic(0x22385A, 0x22385A)
        static let textPrimary = dynamic(0xE3ECF7, 0xE3ECF7)
        static let textSecondary = dynamic(0x8A9DB8, 0x8A9DB8)
        static let pill = dynamic(0xE3ECF7, 0xE3ECF7)
        static let pillText = dynamic(0x0E1A2B, 0x0E1A2B)
        static let accent = dynamic(0x86B4F0, 0x86B4F0)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
