import SwiftUI
import UIKit

/// 会自己溜达的小螃蟹。
/// - 闲着的时候沿一条横线来回爬，停下来东张西望、挥钳子
/// - 很久没人理就打哈欠，然后睡着冒 zzz
/// - 点一下：缩一下再开心；连戳三下会害羞；睡着时戳它会吓一跳
/// - 长按把它拎起来，跟着手指走，松手掉回线上
/// - 回复的时候听 working 的：想事、写字、写完开心
/// - 看时间：半夜揉眼睛犯困，早上伸懒腰
/// - 打字时扒着输入框往里瞄，删字就捂眼
/// - 听 cue 的：冒小爱心、抱着花跑一圈、学你贴的表情
/// - 往下一划把它拍扁，委屈几秒再鼓回来
/// - 戳、拎、拍扁、戳醒都记到 CrabLog（要不要用由你决定）
/// - 收到 .sign 暗号举起小木牌，头顶冒泡念一句；两分钟内点它再念一遍
/// - blushing 为 true 时两颊冒粉
///
/// 放在一条横线上（比如输入框上沿），它就在这条线附近活动；
/// 想让它能被拎到更大的区域，把那块区域的全屏坐标写进 CrabStage.shared.area。
public struct RoamingCrab: View {
    /// 外面给的状态，不是 .idle 时优先显示它
    public var working: CrabState
    /// 关掉就待在原地，只做表情
    public var roams: Bool
    public var pixel: CGFloat
    /// 输入框里现在有几个字（用来偷看 / 捂眼）
    public var typing: Int
    /// 外面递过来的小暗号
    public var cue: CrabCue?
    /// 两颊冒粉
    public var blushing: Bool

    public init(working: CrabState = .idle, roams: Bool = true, pixel: CGFloat = 4.0 / 3,
                typing: Int = 0, cue: CrabCue? = nil, blushing: Bool = false) {
        self.working = working
        self.roams = roams
        self.pixel = pixel
        self.typing = typing
        self.cue = cue
        self.blushing = blushing
    }

    @State private var x: CGFloat = 0.5            // 在可走范围里的位置，0 到 1
    @State private var facingLeft = false
    @State private var mood: CrabState = .wave
    @State private var busy = false
    @State private var lastActivity = Date()
    @State private var pokes: [Date] = []
    @State private var dragX: CGFloat?
    @State private var dragStart: CGFloat = 0
    /// 歇着时离自己那条线多远（往上是负的）；拎起来放到别处就停在那儿
    @State private var y: CGFloat = 0
    /// 拎着的时候跟着手指的高度
    @State private var dragY: CGFloat?
    @State private var dragYStart: CGFloat = 0
    /// 自己那条线在屏幕上的中线高度，算能放多高多低用
    @State private var laneMid: CGFloat = 0
    /// 原地蹦的高度
    @State private var hopY: CGFloat = 0
    /// 她最后一次打字的时间，打字时螃蟹不乱跑
    @State private var lastTyped = Date.distantPast
    @State private var lifted = false
    @State private var moodToken = 0
    /// 暗号触发的动作，比 working 还优先
    @State private var forced: CrabState?
    @State private var forcedToken = 0
    @State private var hearts: [UUID] = []
    /// 正举着牌念的那句；nil 就是没举
    @State private var signText: String?
    /// 最近一句心声，点螃蟹重播
    @State private var lastSign: String?
    @State private var lastSignAt = Date.distantPast
    @State private var signToken = 0
    /// 这一下手指什么时候按下的；nil 表示没在按
    @State private var touchStart: Date?
    /// 按下后挪开超过一点点，就不算长按了
    @State private var touchMoved = false
    @State private var holdTask: Task<Void, Never>?
    @State private var lastTranslation: CGSize = .zero
    /// 拎起来那一刻手指已经挪了多少，拖动从这里算起
    @State private var liftOrigin: CGSize = .zero

    @Environment(\.crabStyle) private var style
    private static let lane = "crabLane"

    private var crabWidth: CGFloat { CGFloat(style.columns + 4) * pixel }
    private var crabHeight: CGFloat { CGFloat(19 + 2) * pixel }
    private let margin: CGFloat = 12

    public var body: some View {
        GeometryReader { geo in
            let span = max(0, geo.size.width - crabWidth - margin * 2)
            let shown: CrabState = lifted ? .surprised : (forced ?? (working != .idle ? working : mood))
            let left = margin + (dragX ?? x * span)
            let crabCenter = left + crabWidth / 2

            CrabView(state: shown, pixel: pixel, flipped: facingLeft && shown.facesSide)
                .background {
                    // 把自己的位置报给开场动画，好让那只爬到这里来
                    GeometryReader { g in
                        Color.clear
                            .onAppear { reportRest(g.frame(in: .global)) }
                            .onChange(of: g.frame(in: .global)) { _, f in reportRest(f) }
                    }
                }
                .overlay {
                    // 脸颊冒两团粉
                    if blushing, shown != .sleeping {
                        BlushCheeks(pixel: pixel)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: blushing)
                .overlay(alignment: .top) {
                    ZStack {
                        ForEach(hearts, id: \.self) { _ in
                            FloatingHeart(pixel: pixel)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    if let signText {
                        let w = Self.bubbleWidth(for: signText, limit: geo.size.width - 24)
                        // 气泡尽量在螃蟹正上方，靠边时往里挪，别出屏幕
                        let center = min(max(crabCenter, 12 + w / 2), geo.size.width - 12 - w / 2)
                        SignBubble(text: signText, width: w, pixel: pixel, tailShift: crabCenter - center)
                            .offset(x: center - crabCenter)
                            .alignmentGuide(.top) { d in d[.bottom] - 2 * pixel }
                            .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                            .allowsHitTesting(false)
                    }
                }
                .animation(.spring(duration: 0.35, bounce: 0.35), value: signText)
                .contentShape(Rectangle().inset(by: -10))
                // 一个手势管三件事，免得几个手势互相抢：
                // 按住不动 0.35 秒拎起来再拖；没按够就划下去是拍扁；轻点一下是戳
                // 手势要挂在 offset 前面，摸的地方才会跟着螃蟹走
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.lane))
                        .onChanged { value in touchChanged(value, span: span) }
                        .onEnded { value in touchEnded(value, span: span) }
                )
                .scaleEffect(lifted ? 1.15 : 1, anchor: .bottom)
                .offset(y: (dragY ?? y) - (lifted ? 6 : 0) + hopY)
                .shadow(color: .black.opacity(lifted ? 0.15 : 0), radius: 6, y: 4)
                .opacity(CrabStage.shared.handedOff ? 1 : 0)
                .position(x: left + crabWidth / 2, y: geo.size.height / 2)
                .animation(.snappy(duration: 0.2), value: lifted)
        }
        .coordinateSpace(name: Self.lane)
        .frame(height: crabHeight + 8)
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { laneMid = g.frame(in: .global).midY }
                    .onChange(of: g.frame(in: .global).midY) { _, v in laneMid = v }
            }
        }
        .onChange(of: working) { _, new in
            busy = new != .idle
            lastActivity = .now
            if busy, mood == .sleeping || mood == .sleepy { mood = .idle }
        }
        .onChange(of: typing) { old, new in handleTyping(from: old, to: new) }
        .onChange(of: cue) { _, new in
            guard let new else { return }
            handle(new)
        }
        .onAppear {
            busy = working != .idle
            greet()
        }
        .task(id: roams) { await wander() }
    }

    // MARK: - 自己溜达

    @MainActor
    private func wander() async {
        while !Task.isCancelled {
            // 闲着的时候歇一两秒就找点事做
            try? await Task.sleep(for: .seconds(Double.random(in: 1.2...3.2)))
            guard !Task.isCancelled, CrabStage.shared.handedOff, !busy, !lifted, touchStart == nil, dragX == nil, forced == nil else { continue }
            guard mood == .idle || mood == .sleeping else { continue }
            // 她在打字就别乱跑，趴着偷看就行
            guard Date().timeIntervalSince(lastTyped) > 4 else { continue }

            let idleFor = Date().timeIntervalSince(lastActivity)
            let night = TimeOfDay.now == .lateNight
            // 很久没人理才犯困，半夜早一点
            if idleFor > (night ? 150 : 300) {
                if mood != .sleeping {
                    mood = .sleepy
                    try? await Task.sleep(for: .seconds(2.4))
                    if mood == .sleepy { mood = .sleeping }
                }
                continue
            }

            let roll = Double.random(in: 0..<1)
            if roams && roll < 0.6 {
                // 有时候一口气爬两三段，路线就不只是来回横跳
                let legs = Double.random(in: 0..<1) < 0.35 ? Int.random(in: 2...3) : 1
                for _ in 0..<legs {
                    guard !Task.isCancelled, !busy, !lifted, touchStart == nil, forced == nil else { break }
                    await crawl(to: CGFloat.random(in: 0...1), height: pickHeight())
                    try? await Task.sleep(for: .seconds(Double.random(in: 0.2...0.6)))
                }
            } else if roll < 0.7 {
                setMood(.wave, for: 1.1)
            } else if roll < 0.78 {
                await hop(times: Int.random(in: 1...2))
            } else if roll < 0.85 {
                // 夹夹钳子，开心一下
                setMood(.happy, for: 1.0)
            } else if roll < 0.92 {
                await lookAround()
            } else {
                setMood(night ? .rubEyes : .shy, for: 1.4)
            }
        }
    }

    /// 原地蹦一下
    @MainActor
    private func hop(times: Int) async {
        for _ in 0..<times {
            withAnimation(.easeOut(duration: 0.14)) { hopY = -(6 + 3 * pixel) }
            try? await Task.sleep(for: .seconds(0.14))
            withAnimation(.easeIn(duration: 0.16)) { hopY = 0 }
            try? await Task.sleep(for: .seconds(0.22))
        }
    }

    /// 左看看右看看：侧身转一下再转回来
    @MainActor
    private func lookAround() async {
        moodToken += 1
        let token = moodToken
        facingLeft.toggle()
        mood = .walking
        try? await Task.sleep(for: .seconds(0.5))
        guard token == moodToken else { return }
        facingLeft.toggle()
        try? await Task.sleep(for: .seconds(0.5))
        guard token == moodToken else { return }
        mood = .idle
    }

    @MainActor
    private func crawl(to target: CGFloat, height: CGFloat? = nil) async {
        let across = Double(abs(target - x)) * 300   // 横着按屏宽 300pt 算
        let toY = height ?? y
        let down = Double(abs(toY - y))
        let distance = (across * across + down * down).squareRoot()
        guard distance > 24 else { return }
        facingLeft = target < x
        mood = .walking
        // 大约每秒爬 55pt
        let seconds = distance / 55
        withAnimation(.linear(duration: seconds)) {
            x = target
            y = toY
        }
        try? await Task.sleep(for: .seconds(seconds))
        if mood == .walking { mood = .idle }
    }

    /// 溜达时换个高度：有时候回自己那条线，有时候沿着现在这一行，一半多的时候去对话区里随便哪儿
    private func pickHeight() -> CGFloat? {
        let (lo, hi) = yBounds()
        guard hi - lo > 20 else { return nil }
        let roll = Double.random(in: 0..<1)
        if y != 0 && roll < 0.25 { return 0 }
        if roll < 0.45 { return nil }
        return CGFloat.random(in: lo...hi)
    }

    /// 能往上、往下挪多少：不出对话区，不钻进输入框
    private func yBounds() -> (CGFloat, CGFloat) {
        let area = CrabStage.shared.area
        guard area.height > 0, laneMid > 0 else { return (-240, 0) }
        let half = crabHeight / 2
        let lo = min(0, area.minY + half - laneMid)
        let hi = max(0, area.maxY - half - laneMid)
        return (lo, hi)
    }

    private func clampY(_ v: CGFloat) -> CGFloat {
        let (lo, hi) = yBounds()
        return min(max(v, lo), hi)
    }

    /// 开场还没交棒时，把自己的位置报上去
    private func reportRest(_ frame: CGRect) {
        let stage = CrabStage.shared
        guard !stage.handedOff else { return }
        stage.restFrame = frame
        stage.restPixel = pixel
    }

    // MARK: - 看时间打招呼

    private func greet() {
        switch TimeOfDay.now {
        case .lateNight: setMood(.rubEyes, for: 2.2, then: .sleepy, for: 2.4)
        case .morning: setMood(.stretch, for: 2.2)
        default: setMood(.wave, for: 1.2)
        }
    }

    // MARK: - 偷看输入框

    private func handleTyping(from old: Int, to new: Int) {
        lastTyped = .now
        guard !busy, !lifted, forced == nil else { return }
        lastActivity = .now
        if new > old {
            setMood(.peek, for: 1.6)
        } else if new < old {
            // 一下子清空多半是发出去了，不算删字
            if new == 0 && old - new > 3 { return }
            setMood(.coverEyes, for: 0.9)
        }
    }

    // MARK: - 暗号

    private func handle(_ cue: CrabCue) {
        lastActivity = .now
        switch cue.kind {
        case .heart:
            popHeart()
        case .flower:
            Task { await flowerLap() }
        case .reaction(let emoji):
            mimic(emoji)
        case .sign(let text):
            lastSign = text
            lastSignAt = .now
            showSign(text)
        }
    }

    /// 举牌：停在原地举起小木牌，头顶冒泡念一会儿，再收起来接着溜达
    private func showSign(_ text: String) {
        guard !lifted, forced != .squashed else { return }
        signToken += 1
        let token = signToken
        let seconds = min(9, max(3.2, 2.2 + Double(text.count) * 0.12))
        if mood == .sleeping || mood == .sleepy { mood = .idle }
        haptic(.soft)
        signText = text
        setForced(.wave, for: seconds)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if token == signToken { signText = nil }
        }
    }

    private func hideSign() {
        signToken += 1
        signText = nil
        forcedToken += 1
        forced = nil
    }

    /// 气泡宽度：按字数估，最宽 220
    private static func bubbleWidth(for text: String, limit: CGFloat) -> CGFloat {
        let estimate = CGFloat(text.count) * 13 + 24
        return max(60, min(estimate, 220, limit))
    }

    /// 跟着你贴的表情做同款
    private func mimic(_ emoji: String) {
        switch emoji {
        case "❤️":
            popHeart()
            setForced(.happy, for: 1.4)
        case "😂": setForced(.laugh, for: 1.8)
        case "👍": setForced(.wave, for: 1.4)
        case "😭": setForced(.cry, for: 2.0)
        case "😳": setForced(.surprised, for: 1.2)
        case "🥺": setForced(.shy, for: 1.8)
        default: setForced(.happy, for: 1.2)
        }
    }

    private func setForced(_ state: CrabState, for seconds: Double) {
        forcedToken += 1
        let token = forcedToken
        forced = state
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if token == forcedToken { forced = nil }
        }
    }

    private func popHeart() {
        let id = UUID()
        hearts.append(id)
        haptic(.soft)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            hearts.removeAll { $0 == id }
        }
    }

    /// 抱着小花跑到另一头再跑回来
    @MainActor
    private func flowerLap() async {
        guard !lifted else { return }
        forcedToken += 1
        let token = forcedToken
        forced = .flowerRun
        let start = x
        let far: CGFloat = start < 0.5 ? 1 : 0
        for target in [far, start] {
            let seconds = max(0.4, Double(abs(target - x)) * 300 / 110)
            facingLeft = target < x
            withAnimation(.linear(duration: seconds)) { x = target }
            try? await Task.sleep(for: .seconds(seconds))
            guard token == forcedToken else { return }
            if lifted {
                forced = nil
                return
            }
        }
        forced = nil
        setMood(.happy, for: 0.8)
    }

    // MARK: - 拍扁

    private func squash() {
        guard forced != .squashed else { return }
        lastActivity = .now
        pokes = []
        CrabLog.shared.note(.squash)
        CrabHaptics.impact(.heavy)
        forcedToken += 1
        let token = forcedToken
        forced = .squashed
        Task { @MainActor in
            // 委屈地扁一会儿，再噗一下鼓回来
            try? await Task.sleep(for: .seconds(3.2))
            guard token == forcedToken else { return }
            forced = nil
            haptic(.soft)
            setMood(.poked, for: 0.4, then: .shy, for: 1.2)
        }
    }

    // MARK: - 手势

    private static let holdSeconds = 0.35
    private static let moveSlop: CGFloat = 10

    private func touchChanged(_ value: DragGesture.Value, span: CGFloat) {
        lastTranslation = value.translation
        if touchStart == nil {
            touchStart = .now
            touchMoved = false
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.holdSeconds))
                guard !Task.isCancelled, touchStart != nil, !touchMoved, !lifted else { return }
                lift(span: span)
            }
        }
        if lifted {
            let dx = value.translation.width - liftOrigin.width
            let dy = value.translation.height - liftOrigin.height
            dragX = min(max(0, dragStart + dx), span)
            dragY = clampY(dragYStart + dy)
            return
        }
        let t = value.translation
        if !touchMoved && (t.width * t.width + t.height * t.height) > Self.moveSlop * Self.moveSlop {
            touchMoved = true
            holdTask?.cancel()
            holdTask = nil
        }
    }

    private func touchEnded(_ value: DragGesture.Value, span: CGFloat) {
        holdTask?.cancel()
        holdTask = nil
        let held = Date().timeIntervalSince(touchStart ?? .now)
        let moved = touchMoved
        touchStart = nil
        touchMoved = false
        if lifted {
            drop(span: span)
            return
        }
        let t = value.translation
        if moved {
            // 快速往下一划：拍扁
            if t.height > 28 && t.height > abs(t.width) * 1.4 { squash() }
        } else if held < Self.holdSeconds {
            poke()
        }
    }

    // MARK: - 拎起来放下

    private func lift(span: CGFloat) {
        dragStart = x * span
        dragYStart = y
        dragY = y
        liftOrigin = lastTranslation
        lastActivity = .now
        lifted = true
        CrabHaptics.soft(0.7)
    }

    private func drop(span: CGFloat) {
        guard lifted else { return }
        CrabLog.shared.note(.lift)
        if let dragX, span > 0 { x = dragX / span }
        dragX = nil
        lastActivity = .now
        // 放哪儿就停哪儿，落地轻轻弹一下、震一下
        let landed = clampY(dragY ?? y)
        withAnimation(.spring(duration: 0.35, bounce: 0.45)) {
            y = landed
            dragY = nil
            lifted = false
        }
        haptic(.light)
        setMood(.happy, for: 0.9)
    }

    // MARK: - 戳它

    private func poke() {
        // 扁着的时候戳不动
        guard forced != .squashed else { return }
        let now = Date()
        lastActivity = now
        haptic(.light)
        if mood == .sleeping || mood == .sleepy {
            pokes = []
            CrabLog.shared.note(.wake)
            setMood(.surprised, for: 1.0)
            return
        }
        CrabLog.shared.note(.poke)
        // 举着牌时点一下收起来；刚念过的两分钟里点一下再念一遍，之后还是普通的戳
        if signText != nil {
            hideSign()
            return
        }
        if let lastSign, now.timeIntervalSince(lastSignAt) < 120 {
            pokes = []
            showSign(lastSign)
            return
        }
        pokes = pokes.filter { now.timeIntervalSince($0) < 2 } + [now]
        if pokes.count >= 3 {
            pokes = []
            CrabLog.shared.note(.shy)
            setMood(.shy, for: 1.8)
        } else {
            setMood(.poked, for: 0.5, then: .happy, for: 0.9)
        }
    }

    /// 换个表情，过一会儿自己回到 idle；中途被别的表情打断就不管了
    private func setMood(_ m: CrabState, for seconds: Double, then next: CrabState? = nil, for nextSeconds: Double = 0) {
        moodToken += 1
        let token = moodToken
        mood = m
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard token == moodToken else { return }
            if let next {
                mood = next
                try? await Task.sleep(for: .seconds(nextSeconds))
                guard token == moodToken else { return }
            }
            mood = .idle
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        CrabHaptics.impact(style)
    }
}

/// 从螃蟹头上飘起来的小爱心
private struct FloatingHeart: View {
    var pixel: CGFloat
    @State private var up = false
    @State private var drift = CGFloat.random(in: -14...14)

    var body: some View {
        PixelCrab(frame: CrabProps.heart, pixel: max(1.5, pixel * 1.2))
            .scaleEffect(up ? 1.2 : 0.6)
            .offset(x: up ? drift : 0, y: up ? -38 : -4)
            .opacity(up ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3)) { up = true }
            }
    }
}

/// 举牌的样子：上面一个说话气泡写着心声，下面一块像素小木牌，螃蟹举着它
private struct SignBubble: View {
    let text: String
    let width: CGFloat
    let pixel: CGFloat
    /// 气泡挪开以后，小尖还要指着螃蟹
    let tailShift: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.caption)
                .foregroundStyle(CrabTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: width)
                .background(CrabTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CrabTheme.border, lineWidth: 0.6))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            // 小尖
            Triangle()
                .fill(CrabTheme.surface)
                .frame(width: 10, height: 5)
                .offset(x: tailShift)
            PixelSign(pixel: max(1.5, pixel))
                .offset(x: tailShift)
                .padding(.top, 2)
        }
    }
}

/// 像素小木牌：一块牌子一根杆，牌上三个小点
private struct PixelSign: View {
    let pixel: CGFloat
    private let wood = Color(red: 0.80, green: 0.58, blue: 0.36)
    private let dark = Color(red: 0.52, green: 0.34, blue: 0.20)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(dark)
                Rectangle().fill(wood).padding(pixel)
                HStack(spacing: pixel) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(dark).frame(width: pixel, height: pixel)
                    }
                }
            }
            .frame(width: pixel * 9, height: pixel * 5)
            Rectangle().fill(dark).frame(width: pixel, height: pixel * 3)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 脸红：两颊各一小团半透明的粉色像素
private struct BlushCheeks: View {
    let pixel: CGFloat
    private let pink = Color(red: 1.0, green: 0.45, blue: 0.6)

    var body: some View {
        GeometryReader { g in
            let w = pixel * 3
            let h = pixel * 1.5
            ZStack {
                cheek(w, h).position(x: g.size.width * 0.28, y: g.size.height * 0.5)
                cheek(w, h).position(x: g.size.width * 0.70, y: g.size.height * 0.5)
            }
        }
    }

    private func cheek(_ w: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: pixel * 0.5)
            .fill(pink.opacity(0.7))
            .frame(width: w, height: h)
            .blur(radius: pixel * 0.3)
    }
}
