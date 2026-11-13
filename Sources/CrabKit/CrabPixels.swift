import SwiftUI

// 像素帧、颜色、画一帧的视图（app 和小组件扩展共用）

/// 一帧像素画。rows 里每个字符是一个像素，"." 是透明，别的字母查 CrabPalette。
public struct CrabFrame: Sendable {
    public let dy: Int
    public let dx: Int
    public let rows: [String]

    public init(dy: Int, dx: Int, rows: [String]) {
        self.dy = dy
        self.dx = dx
        self.rows = rows
    }
}

public enum CrabPalette {
    public static func color(_ ch: Character) -> Color? {
        switch ch {
        case "r": Color(red: 214/255, green: 122/255, blue: 92/255)
        case "d": Color(red: 186/255, green: 98/255, blue: 70/255)
        case "k": Color(red: 38/255, green: 26/255, blue: 22/255)
        case "p": Color(red: 240/255, green: 150/255, blue: 150/255)
        // 爱心钳子那只
        case "O": Color(red: 92/255, green: 38/255, blue: 30/255)
        case "R": Color(red: 240/255, green: 118/255, blue: 90/255)
        case "H": Color(red: 255/255, green: 178/255, blue: 150/255)
        case "D": Color(red: 206/255, green: 88/255, blue: 64/255)
        case "K": Color(red: 35/255, green: 24/255, blue: 20/255)
        case "W": Color(red: 255/255, green: 250/255, blue: 242/255)
        case "P": Color(red: 255/255, green: 150/255, blue: 170/255)
        case "S": Color(red: 110/255, green: 210/255, blue: 190/255)
        // 小道具：花瓣、花心、花茎、爱心、眼泪
        case "f": Color(red: 246/255, green: 150/255, blue: 180/255)
        case "y": Color(red: 247/255, green: 206/255, blue: 84/255)
        case "g": Color(red: 108/255, green: 176/255, blue: 108/255)
        case "L": Color(red: 236/255, green: 88/255, blue: 112/255)
        case "T": Color(red: 120/255, green: 190/255, blue: 240/255)
        default: nil
        }
    }
}

/// 只画一帧，不带动画。灵动岛 / 小组件里用它，靠外面推新的帧号来换画面。
/// 用 Shape 拼方块，不用 Canvas，小组件里画得最稳。
public struct PixelCrab: View {
    public let frame: CrabFrame
    public var pixel: CGFloat
    public var flipped: Bool

    public init(frame: CrabFrame, pixel: CGFloat = 1, flipped: Bool = false) {
        self.frame = frame
        self.pixel = pixel
        self.flipped = flipped
    }

    private static let inks: [Character] = ["r", "d", "p", "k", "O", "R", "H", "D", "K", "W", "P", "S", "f", "y", "g", "L", "T"]

    public var body: some View {
        let cols = (frame.rows.first?.count ?? 0) + 2
        let rows = frame.rows.count + 1
        ZStack(alignment: .topLeading) {
            ForEach(Self.inks, id: \.self) { ch in
                PixelLayer(frame: frame, ink: ch, pixel: pixel)
                    .fill(CrabPalette.color(ch) ?? .clear, style: FillStyle(antialiased: false))
            }
        }
        .frame(width: CGFloat(cols) * pixel, height: CGFloat(rows) * pixel)
        .scaleEffect(x: flipped ? -1 : 1, y: 1)
    }
}

/// 一种颜色的所有方块
private struct PixelLayer: Shape {
    let frame: CrabFrame
    let ink: Character
    let pixel: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (y, row) in frame.rows.enumerated() {
            for (x, ch) in row.enumerated() where ch == ink {
                path.addRect(CGRect(
                    x: CGFloat(x + frame.dx) * pixel,
                    y: CGFloat(y + frame.dy) * pixel,
                    width: pixel, height: pixel
                ))
            }
        }
        return path
    }
}
