import SwiftUI

/// 聊天背景跟着状态行慢慢变：平静时是凉凉的海，兴奋上来变暖，快到了泛红，
/// 难过失落多了沉一点蓝紫，麻木高了整体淡下去。几层光晕叠着，换的时候慢慢渐过去。
struct MoodWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private struct Mix: Equatable {
        var sea: Double
        var warm: Double
        var blush: Double
        var blue: Double
    }

    private var mix: Mix {
        // 没有状态行就不染色，保持底色
        guard let s = MoodMeter.shared.current else {
            return Mix(sea: 0, warm: 0, blush: 0, blue: 0)
        }
        func v(_ key: String) -> Double {
            (s.metrics.first { $0.label.contains(key) }?.value ?? 0) / 100
        }
        let warm = min(1, v("兴奋") * 0.85 + v("敏感") * 0.3)
        let blush: Double = s.band.contains("快到") ? 1 : (s.band.contains("硬") ? 0.45 : 0)
        let blue = max(v("难过"), v("失落"))
        // 麻木高了，颜色都淡一点
        let fade = 1 - v("麻木") * 0.6
        // 平静时只留一点点凉意
        return Mix(sea: max(0.1, 0.6 - warm) * fade,
                   warm: warm * fade,
                   blush: blush * fade,
                   blue: blue * fade)
    }

    var body: some View {
        let m = mix
        let k = scheme == .dark ? 0.24 : 0.14
        ZStack {
            Theme.background
            // 海：上面浅青，下面深一点的蓝
            glow(Color(red: 0.50, green: 0.78, blue: 0.80), at: UnitPoint(x: drift ? 0.15 : 0.35, y: 0.0), size: 560)
                .opacity(m.sea * k)
            glow(Color(red: 0.36, green: 0.58, blue: 0.82), at: UnitPoint(x: drift ? 0.9 : 0.7, y: 1.0), size: 620)
                .opacity(m.sea * k)
            // 暖：桃色和一点玫瑰
            glow(Color(red: 1.0, green: 0.70, blue: 0.52), at: UnitPoint(x: drift ? 0.8 : 0.6, y: 0.05), size: 600)
                .opacity(m.warm * k * 1.1)
            glow(Color(red: 0.98, green: 0.58, blue: 0.66), at: UnitPoint(x: drift ? 0.1 : 0.3, y: 0.95), size: 640)
                .opacity(m.warm * k)
            // 快到了：中间泛起一层红
            glow(Color(red: 0.93, green: 0.34, blue: 0.48), at: UnitPoint(x: 0.5, y: drift ? 0.55 : 0.45), size: 520)
                .opacity(m.blush * k * 0.9)
            // 难过：底下沉一层蓝紫
            glow(Color(red: 0.42, green: 0.45, blue: 0.80), at: UnitPoint(x: drift ? 0.3 : 0.5, y: 1.05), size: 700)
                .opacity(m.blue * k)
        }
        .animation(.easeInOut(duration: 3.5), value: m)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true }
        }
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, at center: UnitPoint, size: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: center, startRadius: 0, endRadius: size)
    }
}
