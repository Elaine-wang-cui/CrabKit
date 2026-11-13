import SwiftUI

private struct CrabStyleKey: EnvironmentKey {
    static let defaultValue: CrabStyle = .heart
}

extension EnvironmentValues {
    /// 小螃蟹的样式，从最外层一路传下来
    public var crabStyle: CrabStyle {
        get { self[CrabStyleKey.self] }
        set { self[CrabStyleKey.self] = newValue }
    }
}

public enum CrabState: Equatable, CaseIterable, Sendable {
    case idle, thinking, walking, happy
    case wave, sleepy, sleeping, poked, surprised, shy
    case stretch, rubEyes, peek, coverEyes, flowerRun, laugh, cry, squashed
    /// 思考条旁边挠头
    case scratch

    public func frames(_ style: CrabStyle) -> [CrabFrame] {
        heartFrames
    }

    private var heartFrames: [CrabFrame] {
        switch self {
        case .idle: HeartCrabSprites.idle
        case .thinking: HeartCrabSprites.thinking
        case .walking: HeartCrabSprites.walking
        case .happy: HeartCrabSprites.happy
        case .wave: HeartCrabSprites.wave
        case .sleepy: HeartCrabSprites.sleepy
        case .sleeping: HeartCrabSprites.sleeping
        case .poked: HeartCrabSprites.poked
        case .surprised: HeartCrabSprites.surprised
        case .shy: HeartCrabSprites.shy
        case .stretch: HeartCrabSprites.stretch
        case .rubEyes: HeartCrabSprites.rubEyes
        case .peek: HeartCrabSprites.peek
        case .coverEyes: HeartCrabSprites.coverEyes
        case .flowerRun: HeartCrabSprites.flowerRun
        case .laugh: HeartCrabSprites.laugh
        case .cry: HeartCrabSprites.cry
        case .squashed: HeartCrabSprites.squashed
        case .scratch: HeartCrabSprites.scratch
        }
    }

    /// 侧身的状态（这只爱心钳子一直正面，不会转到侧身）
    public var facesSide: Bool { self == .thinking || self == .walking }

    public var interval: TimeInterval {
        switch self {
        case .idle: 0.45
        case .thinking: 0.16
        case .walking: 0.14
        case .happy: 0.22
        case .wave: 0.18
        case .sleepy: 0.4
        case .sleeping: 0.8
        case .poked: 0.12
        case .surprised: 0.14
        case .shy: 0.35
        case .stretch: 0.32
        case .rubEyes: 0.22
        case .peek: 0.4
        case .coverEyes: 0.12
        case .flowerRun: 0.1
        case .laugh: 0.12
        case .cry: 0.3
        case .squashed: 0.35
        case .scratch: 0.2
        }
    }

    /// 工作时下面那行小字，会轮换
    public var captions: [String] {
        switch self {
        case .thinking: ["夹着想法", "吐泡泡", "在沙里刨", "翻小本子"]
        case .walking: ["横着爬过来", "边走边写", "钳子打字中"]
        case .happy: ["写好啦"]
        default: ["我在呢"]
        }
    }
}

/// 小螃蟹。pixel 是每个像素点的边长。
public struct CrabView: View {
    public var state: CrabState
    public var pixel: CGFloat
    /// 往左爬的时候把侧身翻过来
    public var flipped: Bool
    public var style: CrabStyle?

    public init(state: CrabState, pixel: CGFloat = 3, flipped: Bool = false, style: CrabStyle? = nil) {
        self.state = state
        self.pixel = pixel
        self.flipped = flipped
        self.style = style
    }

    @Environment(\.crabStyle) private var chosenStyle
    private var shownStyle: CrabStyle { style ?? chosenStyle }

    /// 左右各留 2 格给走路时的横移，上下各留 1 格
    private let padX = 2, padY = 1

    /// 正面和侧身之间切换时，先播一遍转身帧再进循环
    @State private var turnFrames: [CrabFrame] = []
    @State private var changedAt = Date.distantPast
    private static let turnStep: TimeInterval = 0.08

    public var body: some View {
        TimelineView(.periodic(from: .now, by: min(state.interval, Self.turnStep))) { context in
            let frames = state.frames(shownStyle)
            let since = context.date.timeIntervalSince(changedAt)
            let turnIndex = Int(since / Self.turnStep)
            let looping = max(0, since - Double(turnFrames.count) * Self.turnStep)
            let frame = turnIndex < turnFrames.count
                ? turnFrames[max(0, turnIndex)]
                : frames[Int(looping / state.interval) % frames.count]
            let cols = frames[0].rows.first?.count ?? 0
            let rowsCount = frames[0].rows.count
            Canvas { gc, _ in
                // 同色的格子拼成一条路径，关掉抗锯齿，小尺寸时格子之间不会有细缝
                var paths: [Character: Path] = [:]
                for (y, row) in frame.rows.enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." {
                        let rect = CGRect(
                            x: CGFloat(x + frame.dx + padX) * pixel,
                            y: CGFloat(y + frame.dy + padY) * pixel,
                            width: pixel, height: pixel
                        )
                        paths[ch, default: Path()].addRect(rect)
                    }
                }
                for (ch, path) in paths {
                    guard let color = CrabPalette.color(ch) else { continue }
                    gc.fill(path, with: .color(color), style: FillStyle(antialiased: false))
                }
            }
            .frame(width: CGFloat(cols + padX * 2) * pixel, height: CGFloat(rowsCount + padY * 2) * pixel)
            .scaleEffect(x: flipped && shownStyle.turnsSideways ? -1 : 1, y: 1)
            .overlay(alignment: .topTrailing) {
                if state == .sleeping {
                    // 睡着冒 zzz
                    let n = Int(since / 0.8) % 3 + 1
                    Text(String(repeating: "z", count: n))
                        .font(.system(size: max(9, pixel * 4), weight: .semibold, design: .rounded))
                        .foregroundStyle(CrabTheme.textSecondary)
                        .offset(x: pixel * 2, y: -pixel * 3)
                }
            }
        }
        .onChange(of: shownStyle) { _, _ in
            turnFrames = []
            changedAt = Date()
        }
        .onChange(of: state) { _, _ in
            turnFrames = []
            changedAt = Date()
        }
        .accessibilityLabel("小螃蟹")
    }

}

/// 干活时的那只：小螃蟹 + 轮换的小字（比如贴在一条正在生成的消息下面）
public struct WorkingCrab: View {
    public var state: CrabState
    /// 想事情时头上冒泡泡
    public var bubbles: Bool

    public init(state: CrabState, bubbles: Bool = false) {
        self.state = state
        self.bubbles = bubbles
    }

    public var body: some View {
        HStack(spacing: 8) {
            CrabView(state: state, pixel: 4.0 / 3)
                .overlay(alignment: .top) {
                    if bubbles && state == .thinking {
                        CrabBubbles()
                            .frame(width: 26, height: 34)
                            .offset(x: 4, y: -30)
                            .transition(.opacity)
                    }
                }
            TimelineView(.periodic(from: .now, by: 1.8)) { context in
                let captions = state.captions
                let i = Int(context.date.timeIntervalSinceReferenceDate / 1.8) % captions.count
                Text(captions[i] + "…")
                    .font(.footnote)
                    .foregroundStyle(CrabTheme.textSecondary)
                    .contentTransition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack(spacing: 24) {
        CrabView(state: .idle, pixel: 6)
        WorkingCrab(state: .thinking)
        WorkingCrab(state: .walking)
    }
    .padding()
    .background(CrabTheme.background)
}
