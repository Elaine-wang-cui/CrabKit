import SwiftUI

/// 夜海配色背景里慢慢往上飘、一闪一闪的小光点
struct NightSpecks: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var count = 38

    private struct Speck {
        let x: Double, y: Double, speed: Double, size: Double, twinkle: Double, phase: Double
    }

    private let specks: [Speck] = (0..<60).map { i in
        func r(_ k: Double) -> Double {
            let v = sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453
            return v - floor(v)
        }
        return Speck(x: r(1), y: r(2), speed: 0.004 + r(3) * 0.012,
                     size: 0.8 + r(4) * 1.6, twinkle: 0.6 + r(5) * 1.6, phase: r(6) * 6.28)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                for s in specks.prefix(count) {
                    var y = (s.y - t * s.speed).truncatingRemainder(dividingBy: 1)
                    if y < 0 { y += 1 }
                    let x = s.x + 0.012 * sin(t * 0.25 + s.phase)
                    let glow = 0.5 + 0.5 * sin(t * s.twinkle + s.phase)
                    let p = CGPoint(x: x * size.width, y: y * size.height)
                    let r = s.size * (0.8 + 0.4 * glow)
                    // 外面一圈虚光，里面一颗亮点
                    gc.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                            with: .color(Color(red: 0.62, green: 0.76, blue: 1.0).opacity(0.08 * glow)))
                    gc.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                            with: .color(Color(red: 0.86, green: 0.92, blue: 1.0).opacity(0.25 + 0.5 * glow)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
