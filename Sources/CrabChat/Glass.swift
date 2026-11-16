import SwiftUI

/// 毛玻璃底：开着时是磨砂加一层淡淡的本色，后面的背景和螃蟹透得过来；关了就是原来的实色
extension View {
    func glass<S: Shape>(_ shape: S, tint: Color, on: Bool, strength: Double = 0.4) -> some View {
        background {
            if on {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint.opacity(strength)))
                    .overlay(shape.stroke(Color.white.opacity(0.22), lineWidth: 0.6).blendMode(.plusLighter))
            } else {
                shape.fill(tint)
            }
        }
    }
}

/// 顶栏的毛玻璃：上面实一点，往下渐渐透明，对话滑上去时糊糊地透出来
struct GlassBarBackground: View {
    let on: Bool

    var body: some View {
        if on {
            // 磨砂和一层同底色一起往下慢慢淡掉，还往栏下面多拖一截，看不出边
            let fade = LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.95), location: 0.55),
                .init(color: .black.opacity(0.7), location: 0.75),
                .init(color: .black.opacity(0.3), location: 0.9),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                // Thick enough that a stray icon scrolling under the bar fades out instead of sitting on top
                Theme.background.opacity(0.6)
            }
            .mask(fade)
            .padding(.bottom, -36)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        } else {
            // Solid bar, with a short soft edge below it so content slides under instead of being cut
            Theme.background
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom))
                .padding(.bottom, -24)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
        }
    }
}

/// 他的回复：苹果那种玻璃。iOS 26 用系统的 Liquid Glass，老系统用磨砂加一圈亮边顶上
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    /// 铺满样式里淡一点
    var subtle = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), !subtle {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content, shape)
        }
        #else
        fallback(content, shape)
        #endif
    }

    private func fallback(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background {
                shape.fill(subtle ? .ultraThinMaterial : .thinMaterial)
                    .opacity(subtle ? 0.75 : 1)
            }
            .overlay {
                // 边上一圈亮光：左上亮，右下淡，像玻璃的边
                shape.strokeBorder(
                    LinearGradient(colors: [
                        .white.opacity(scheme == .dark ? 0.35 : 0.85),
                        .white.opacity(0.05),
                        .white.opacity(scheme == .dark ? 0.15 : 0.4),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: subtle ? 0.6 : 0.9
                )
            }
            .shadow(color: .black.opacity(subtle ? 0.03 : 0.07), radius: subtle ? 6 : 10, y: subtle ? 2 : 4)
    }
}
