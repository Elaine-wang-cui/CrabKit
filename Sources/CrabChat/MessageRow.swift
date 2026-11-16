import CrabKit
import SwiftUI
import UIKit

/// The branch item reads `isStreaming` itself, so the row around it does not
/// rebuild when a turn starts or ends. Hidden while streaming, same as before.
struct ForkMenuButton: View {
    var session: ChatSession
    var message: ChatMessage
    var title: String

    var body: some View {
        if !session.isStreaming {
            Button {
                session.fork(at: message)
            } label: {
                Label(title, systemImage: "arrow.triangle.branch")
            }
        }
    }
}

/// 往左划看时间：最多划出这么宽；有回复在翻版本时不抢
enum TimeReveal {
    static let full: CGFloat = 62
    static var busy = false
}

struct MessageRow: View {
    let message: ChatMessage
    var session: ChatSession? = nil
    var isLive: Bool = false
    var crab: CrabState = .idle
    var onRegenerate: (() -> Void)? = nil
    /// 长按回复贴表情；传空字符串是取消
    var onReact: ((String) -> Void)? = nil
    /// 点心声小字：让螃蟹再举一次牌
    var onVoice: ((String) -> Void)? = nil
    /// 翻到第几版（重新生成留下的），nil 就是不让翻
    var onVersion: ((Int) -> Void)? = nil
    /// 整页往左划的距离：划出右边的时间
    var timeReveal: CGFloat = 0
    @Environment(ChatChrome.self) private var settings
    /// 左右划着翻版本时，回复跟着手指挪一点
    @State private var dragX: CGFloat = 0
    @State private var zoomed: Attachment?
    /// 在这里看着它写完的，心声才慢慢浮出来；翻旧消息直接显示
    @State private var wasLive = false
    /// 气泡下面那片小叶子点开了
    @State private var showRecalled = false
    @Environment(\.reading) private var reading
    @Environment(\.sendFlightTarget) private var sendFlightTarget

    /// 拆出心声后剩下的正文；原样模式不拆
    private var parts: InnerVoice.Parts {
        guard message.role == .assistant, settings.voiceStyle != "plain" else {
            return InnerVoice.Parts(body: message.text)
        }
        return InnerVoice.split(message.text, live: isLive)
    }

    private var bubbleStyle: Bool { settings.replyStyle == .bubble }
    /// 铺满时文字贴边，和输入框对齐；气泡样式也贴着左边
    private var inset: CGFloat { bubbleStyle ? 2 : 0 }

    var body: some View {
        Group {
            switch message.role {
            case .user: userSide
            case .assistant: assistantBody
            }
        }
        .offset(x: -timeReveal)
        .overlay(alignment: .topTrailing) {
            if timeReveal > 0 {
                Text(Self.stamp(message.createdAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                    .opacity(Double(min(1, timeReveal / TimeReveal.full)))
                    .offset(x: TimeReveal.full - timeReveal - 6, y: message.role == .user ? 14 : 2)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { if isLive { wasLive = true } }
        .onChange(of: isLive) { _, live in if live { wasLive = true } }
        .fullScreenCover(item: $zoomed) { a in
            if let ui = ThumbCache.image(for: a) {
                ImageViewer(image: ui)
            }
        }
    }

    // MARK: You

    private var userSide: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // The spacer caps the bubble the way the old row did. The anchor sits on the
            // tight cluster, not the spacer, so the flight lands on the bubble itself.
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 48)
                UserBubbleCluster(
                    text: message.text,
                    attachments: message.attachments,
                    onZoom: { zoomed = $0 },
                    session: session,
                    message: message
                )
                .background {
                    SendFlightAnchor(on: message.id == sendFlightTarget)
                }
                // Take the leftover width so the text wraps, then hug the bubble for the flight anchor.
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !message.recalled.isEmpty {
                recalledLeaf
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 这条消息上可选的一段备注。平时是一片小叶子，点开才看见文字。
    private var recalledLeaf: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button {
                withAnimation(.snappy) { showRecalled.toggle() }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "leaf")
                    Text(showRecalled ? "Hide" : "Remembered something")
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            if showRecalled {
                Text(message.recalled)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.trailing, 6)
    }

    // MARK: Assistant

    private var assistantBody: some View {
        // 正在想：思考条里的螃蟹挠头，下面那只就先不出来，免得两只
        let thinkingLive = isLive && message.text.isEmpty && crab == .thinking
        let bubbles = settings.thinkingLook != "bar"
        // 吐泡泡模式：想的时候不出灰条，想完了再出来能点开看
        let showsBar = settings.showThinking && !message.thinking.isEmpty && !(bubbles && thinkingLive)
        let split = parts
        return VStack(alignment: .leading, spacing: 10) {
            if showsBar {
                ThinkingDisclosure(text: message.thinking, seconds: message.thinkingSeconds, live: thinkingLive)
                    .padding(.leading, inset)
            }
            if !message.toolNotes.isEmpty {
                FlowChips(items: message.toolNotes)
                    .padding(.leading, inset)
            }
            replyFlow(split)
            if !isLive && !split.isEmpty {
                voiceView(split)
            }
            if Speaker.shared.failedID == message.id {
                Label(Speaker.shared.errorText, systemImage: "speaker.slash")
                    .font(.footnote)
                    .padding(.leading, inset)
                    .foregroundStyle(Color.red.opacity(0.8))
            }
            if !message.notice.isEmpty {
                Label(message.notice, systemImage: message.isError ? "exclamationmark.triangle" : "info.circle")
                    .font(.footnote)
                    .padding(.leading, inset)
                    .foregroundStyle(message.isError ? Color.red.opacity(0.8) : Theme.textSecondary)
            }
            if isLive {
                if !(showsBar && thinkingLive) {
                    WorkingCrab(state: crab, bubbles: bubbles)
                        .padding(.leading, inset)
                        .padding(.top, bubbles && crab == .thinking ? 26 : 0)
                }
            } else if !message.text.isEmpty {
                actions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func replyFlow(_ split: InnerVoice.Parts) -> some View {
        let calls = message.toolCalls.filter { settings.toolShow($0.kind) != "hidden" }
        if calls.isEmpty {
            if !split.body.isEmpty {
                replyContent(split.body)
                    .offset(x: dragX)
                    .simultaneousGesture(versionSwipe)
            }
        } else {
            toolPieces(split.body, calls: calls)
        }
    }

    /// 工具卡片插在调用那一刻正文写到的地方
    private func toolPieces(_ body: String, calls: [ToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ToolPiece.split(body, calls: calls).enumerated()), id: \.offset) { _, piece in
                pieceRow(piece)
            }
        }
        .offset(x: dragX)
        .simultaneousGesture(versionSwipe)
    }

    @ViewBuilder
    private func pieceRow(_ piece: ToolPiece) -> some View {
        switch piece {
        case .text(let text):
            replyContent(text)
        case .card(let call):
            ToolCallCard(call: call, startExpanded: settings.toolShow(call.kind) == "expanded")
                .padding(.leading, inset)
        }
    }

    /// 心声：耳语气泡，或者螃蟹举牌时留在回复下面的一行淡淡小字
    @ViewBuilder
    private func voiceView(_ split: InnerVoice.Parts) -> some View {
        let mood = settings.showMeter ? MoodStatus.parse(split.status) : nil
        if settings.voiceRule {
            // 正文和心声之间一根短短的细线
            Rectangle()
                .fill(Theme.border)
                .frame(width: 36, height: 0.8)
                .padding(.leading, inset)
                .padding(.top, 2)
        }
        if let mood {
            StatusDashboard(status: mood, animate: wasLive)
                .padding(.leading, inset)
        }
        // 状态行做成仪表了，下面就只剩心声那句
        let line = InnerVoice.Parts(body: "", status: mood == nil ? split.status : nil, voice: split.voice)
        if !line.isEmpty {
            voiceLine(line)
        }
    }

    @ViewBuilder
    private func voiceLine(_ split: InnerVoice.Parts) -> some View {
        if settings.voiceStyle == "whisper" {
            WhisperBubble(status: split.status, voice: split.voice, animate: wasLive)
                .padding(.leading, inset)
        } else {
            Button {
                if let v = split.voice { onVoice?(v) }
            } label: {
                (Text(split.status.map { $0 + "  " } ?? "").font(.caption2)
                 + Text(split.voice ?? "").font(.caption.italic()))
                    .foregroundStyle(Theme.textSecondary.opacity(0.55))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.leading, inset)
            .accessibilityLabel("Inner voice. Tap to have the crab hold it up again")
        }
    }

    /// 正文：铺满或气泡。长按时背景虚化、这块浮起来，下面出表情、复制、重新生成
    @ViewBuilder
    private func replyContent(_ shown: String) -> some View {
        if bubbleStyle {
            HStack(spacing: 0) {
                MarkdownView(text: shown, fadeIn: isLive, fillsWidth: false)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .modifier(ReplyBubbleBackground(glass: settings.glassReplies))
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contextMenu { if !isLive { replyMenu } }
                Spacer(minLength: 40)
            }
            .padding(.leading, inset)
        } else {
            // 铺满：字直接写在底上，没有气泡也没有卡片
            MarkdownView(text: shown, fadeIn: isLive)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contextMenu { if !isLive { replyMenu } }
                // 长按浮起来时四周留一点边，平时把这圈边吃回去，字照样贴边
                .padding(.leading, inset - 10)
                .padding(.trailing, -10)
                .padding(.vertical, -6)
        }
    }

    @ViewBuilder
    private var replyMenu: some View {
        if let onReact {
            Picker("React", selection: Binding(get: { message.reaction }, set: { onReact($0) })) {
                ForEach(CrabCue.reactions, id: \.self) { emoji in
                    Text(emoji).tag(emoji)
                }
            }
            .pickerStyle(.palette)
        }
        Button {
            UIPasteboard.general.string = parts.body
                Haptics.copied()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button {
            Speaker.shared.toggle(message, settings: settings)
        } label: {
            if Speaker.shared.isBusy(message.id) {
                Label("Stop reading", systemImage: "stop.circle")
            } else {
                Label("Read aloud", systemImage: "speaker.wave.2")
            }
        }
        if let onRegenerate {
            Button(action: onRegenerate) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
        if let session {
            ForkMenuButton(session: session, message: message, title: "Branch from here")
        }
        if let onReact, !message.reaction.isEmpty {
            Button(role: .destructive) {
                onReact("")
            } label: {
                Label("Remove reaction", systemImage: "xmark.circle")
            }
        }
    }

    /// 今天的只写几点几分，更早的带上日子
    static func stamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        if cal.isDateInYesterday(date) { return "Yesterday " + date.formatted(.dateTime.hour().minute()) }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private var canFlip: Bool { onVersion != nil && !isLive && message.versionCount > 1 }

    private func flip(by step: Int) {
        let target = message.versionIndex + step
        guard canFlip, target >= 0, target < message.versionCount else { return }
        withAnimation(.snappy) { onVersion?(target) }
    }

    /// 横着划：往左是下一版，往右是上一版；竖着滑照常滚动
    private var versionSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { v in
                guard canFlip, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                // 这条在翻版本，整页的左划看时间就先让开
                TimeReveal.busy = true
                dragX = max(-40, min(40, v.translation.width * 0.35))
            }
            .onEnded { v in
                defer {
                    TimeReveal.busy = false
                    withAnimation(.spring(duration: 0.3)) { dragX = 0 }
                }
                guard canFlip, abs(v.translation.width) > 60,
                      abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                flip(by: v.translation.width < 0 ? 1 : -1)
            }
    }

    /// ‹ 2/3 ›
    private var versionPager: some View {
        HStack(spacing: 6) {
            Button { flip(by: -1) } label: { Image(systemName: "chevron.left") }
                .disabled(message.versionIndex <= 0)
                .opacity(message.versionIndex <= 0 ? 0.35 : 1)
                .accessibilityLabel("Previous version")
            Text("\(message.versionIndex + 1)/\(message.versionCount)")
                .font(.caption.monospacedDigit())
            Button { flip(by: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(message.versionIndex >= message.versionCount - 1)
                .opacity(message.versionIndex >= message.versionCount - 1 ? 0.35 : 1)
                .accessibilityLabel("Next version")
        }
    }

    /// 小字：命中 12.3k · 写 0.4k · 新 0.1k
    private var cacheLabel: String? {
        let total = message.cacheRead + message.cacheWrite + message.freshInput
        guard total > 0 else { return nil }
        func k(_ n: Int) -> String {
            n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
        }
        var parts: [String] = []
        if message.cacheRead > 0 { parts.append("cached " + k(message.cacheRead)) }
        if message.cacheWrite > 0 { parts.append("wrote " + k(message.cacheWrite)) }
        if parts.isEmpty { return "uncached " + k(total) }
        if message.freshInput > 0 { parts.append("new " + k(message.freshInput)) }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 18) {
            if canFlip {
                versionPager
            }
            Button {
                UIPasteboard.general.string = parts.body
                Haptics.copied()
            } label: { Image(systemName: "doc.on.doc") }
            if let onRegenerate {
                Button(action: onRegenerate) { Image(systemName: "arrow.clockwise") }
            }
            // 念着或者正在要声音时，出个小喇叭，点一下停
            if Speaker.shared.isBusy(message.id) {
                Button { Speaker.shared.stop() } label: {
                    Image(systemName: Speaker.shared.loadingID == message.id ? "ellipsis" : "speaker.wave.2.fill")
                        .symbolEffect(.variableColor.iterative, isActive: Speaker.shared.playingID == message.id)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Stop")
            }
            if !message.reaction.isEmpty {
                // 贴上的表情，点一下螃蟹再做一遍
                Button {
                    onReact?(message.reaction)
                } label: {
                    Text(message.reaction)
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }
            }
            if settings.showCacheStats, let label = cacheLabel {
                Spacer(minLength: 8)
                Label(label, systemImage: message.cacheRead > 0 ? "bolt.fill" : "bolt")
                    .font(.caption2.monospacedDigit())
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Theme.textSecondary.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .buttonStyle(.plain)
        .padding(.top, 2)
        .padding(.leading, inset)
    }
}

/// 思考条：灰色的一条胶囊。想的时候螃蟹在旁边挠头，字上有一道光扫过去；
/// 想完写「想了 N 秒」。点一下展开看思考过程，再点收起来。
struct ThinkingDisclosure: View {
    let text: String
    let seconds: Double
    let live: Bool
    @State private var open = false

    private var label: String {
        if live { return "Thinking" }
        let s = Int(seconds.rounded())
        return s >= 1 ? "Thought for \(s)s" : "Thought briefly"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: 7) {
                    if live {
                        CrabView(state: .scratch, pixel: 1)
                    } else {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 13))
                    }
                    if live {
                        ShimmerText(text: label + "…")
                    } else {
                        Text(label)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.thinkingBar, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide thinking" : "Show thinking")

            if open {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(Theme.border).frame(width: 2)
                    }
                    .padding(.trailing, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 灰字上一道亮光从左扫到右
private struct ShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { context in
            let period = 1.8
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            Text(text)
                .overlay {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(
                            colors: [.clear, Theme.textPrimary.opacity(0.85), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: w * 0.6)
                        .offset(x: -w * 0.6 + (w * 1.6) * t)
                    }
                    .mask { Text(text) }
                    .allowsHitTesting(false)
                }
        }
    }
}

struct FlowChips: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Label(item, systemImage: item.hasPrefix("Notes") ? "leaf" : "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
            }
        }
    }
}

/// 耳语气泡：回复写完停一拍，下面淡淡浮出一个小一号的半透明气泡，斜体轻声说心声。
/// 点一下收成一个小点，再点又打开
struct WhisperBubble: View {
    let status: String?
    let voice: String?
    /// 刚看着写完的才慢慢浮出来
    let animate: Bool
    @State private var shown = false
    @State private var folded = false

    var body: some View {
        Group {
            if folded {
                Image(systemName: "ellipsis")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.5), in: Capsule())
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    if let status, !status.isEmpty {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }
                    if let voice {
                        Text(voice)
                            .font(.footnote.italic())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .padding(.top, 5)
                .background(Theme.surface.opacity(0.55), in: WhisperShape())
                .overlay(WhisperShape().stroke(Theme.border.opacity(0.5), lineWidth: 0.5))
                .frame(maxWidth: 280, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.snappy(duration: 0.25)) { folded.toggle() }
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 5)
        .blur(radius: shown ? 0 : 2)
        .onAppear {
            if animate {
                withAnimation(.easeOut(duration: 0.7).delay(0.6)) { shown = true }
            } else {
                shown = true
            }
        }
        .accessibilityLabel(voice ?? status ?? "Inner voice")
    }
}

/// 圆角气泡，左上角有一个朝上的小尖，像是从回复里冒出来的
struct WhisperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        let body = CGRect(x: rect.minX, y: rect.minY + 5, width: rect.width, height: rect.height - 5)
        var p = Path(roundedRect: body, cornerRadius: r, style: .continuous)
        p.move(to: CGPoint(x: rect.minX + 16, y: body.minY + 0.5))
        p.addLine(to: CGPoint(x: rect.minX + 21, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + 26, y: body.minY + 0.5))
        p.closeSubpath()
        return p
    }
}

/// 气泡样式里他的气泡：玻璃，或者原来的白底细边
private struct ReplyBubbleBackground: ViewModifier {
    let glass: Bool

    func body(content: Content) -> some View {
        if glass {
            content.modifier(GlassCard(cornerRadius: 20))
        } else {
            content
                .background(Theme.assistantBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 0.6))
        }
    }
}

/// 正文切成一段段字和工具卡片
enum ToolPiece {
    case text(String)
    case card(ToolCall)

    static func split(_ body: String, calls: [ToolCall]) -> [ToolPiece] {
        let chars = Array(body)
        var out: [ToolPiece] = []
        var cursor = 0
        func flush(to end: Int) {
            guard end > cursor else { return }
            let t = String(chars[cursor..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.text(t)) }
            cursor = end
        }
        for call in calls.sorted(by: { $0.offset < $1.offset }) {
            flush(to: min(max(call.offset, cursor), chars.count))
            out.append(.card(call))
        }
        flush(to: chars.count)
        return out
    }
}

/// One tool call in a reply: what it was, what went in, what came back. Tap to open.
struct ToolCallCard: View {
    let call: ToolCall
    let startExpanded: Bool
    @State private var open: Bool?

    private var isOpen: Bool { open ?? startExpanded }

    private var icon: String {
        switch call.kind {
        case .memory: "brain.head.profile"
        case .notes: "leaf"
        case .connector: "point.3.connected.trianglepath.dotted"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { open = !isOpen }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 8) {
                    if call.done {
                        Image(systemName: call.isError ? "exclamationmark.triangle" : icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(call.isError ? Color.red.opacity(0.8) : Theme.textSecondary)
                            .frame(width: 18)
                    } else {
                        ProgressView().controlSize(.mini).frame(width: 18)
                    }
                    (Text(call.label).fontWeight(.medium) + Text("  ") + Text(call.name).font(.system(.footnote, design: .monospaced)))
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if !isOpen, !call.summary.isEmpty {
                        Text(call.summary.replacingOccurrences(of: "\n", with: " "))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Rectangle().fill(Theme.border).frame(height: 0.5)
                VStack(alignment: .leading, spacing: 10) {
                    section("Input", call.input.isEmpty ? "(none)" : call.input)
                    section(call.isError ? "Error" : "Result", call.done ? call.result : "Waiting…")
                }
                .padding(12)
                .transition(.opacity)
            }
        }
        .background(Theme.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 0.6))
        .frame(maxWidth: 560, alignment: .leading)
    }

    @ViewBuilder
    private func section(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            let txt = Text(content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if content.count > 700 {
                ScrollView { txt }.frame(height: 220)
            } else {
                txt
            }
        }
    }
}
