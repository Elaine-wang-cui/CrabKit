import SwiftUI

/// 想事情的时候，小螃蟹在底下咕嘟咕嘟吐泡泡，泡泡浮到顶上啵一下没了
public struct CrabBubbles: View {
    public var tint: Color
    public init(tint: Color = CrabTheme.accent) { self.tint = tint }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let count = 5
                for i in 0..<count {
                    let period = 2.2 + Double(i % 3) * 0.35
                    var p = (t / period + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                    if p < 0 { p += 1 }
                    let r = 1.6 + p * 3.2
                    let x = size.width * 0.35 + sin(p * 7 + Double(i) * 1.7) * 4 + Double(i % 2) * 5
                    let y = size.height - 4 - p * (size.height - 8)
                    // 快到顶时变淡，最后撑大一点再没
                    let fade = p < 0.8 ? 1 : max(0, (1 - p) / 0.2)
                    let pop = p > 0.92 ? 1 + (p - 0.92) * 6 : 1
                    let rect = CGRect(x: x - r * pop, y: y - r * pop, width: r * 2 * pop, height: r * 2 * pop)
                    gc.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.55 * fade)), lineWidth: 1)
                    // 泡泡上的小高光
                    let shine = CGRect(x: rect.minX + r * 0.45, y: rect.minY + r * 0.4, width: r * 0.5, height: r * 0.5)
                    gc.fill(Path(ellipseIn: shine), with: .color(Color.white.opacity(0.7 * fade)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
