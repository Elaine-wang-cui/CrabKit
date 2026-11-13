import SwiftUI
import UIKit

/// 小螃蟹周边用到的几种颜色（气泡、小字、泡泡）。
/// 都是可改的：在 app 启动时换成你自己的配色就行。
public enum CrabTheme {
    public static var accent: Color = dynamic(0xE9704F, 0xE9704F)
    public static var background: Color = dynamic(0xF9F8F6, 0x262624)
    public static var surface: Color = dynamic(0xFFFFFF, 0x302D29)
    public static var border: Color = dynamic(0xE5E3DE, 0x3D3934)
    public static var textPrimary: Color = dynamic(0x2A2622, 0xEDE8DF)
    public static var textSecondary: Color = dynamic(0x857D72, 0x9C958B)

    /// 浅色 / 深色各一个十六进制颜色
    public static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(crabHex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(crabHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
