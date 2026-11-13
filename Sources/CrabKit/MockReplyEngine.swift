import Foundation
import Observation

/// 假的「回复引擎」：不连任何服务器，只按固定节奏把螃蟹从 思考 → 写字 → 开心 走一遍，
/// 顺便吐出一段假回复。想接你自己的后端，就照这个样子在真实的流式回调里改 state / cue。
@MainActor @Observable
public final class MockReplyEngine {
    /// 当前给螃蟹的工作状态
    public private(set) var state: CrabState = .idle
    /// 递给螃蟹的暗号
    public private(set) var cue: CrabCue?
    /// 「流」出来的假回复
    public private(set) var text: String = ""
    public var isRunning: Bool { task != nil }

    /// 要不要同时驱动灵动岛
    public var useIsland = false
    public var style: CrabStyle = .heart

    private var task: Task<Void, Never>?
    private var serial = 0

    public static let sampleReplies = [
        "今天也辛苦啦，抱抱你。",
        "我想了想，先把最难的那件事做完，剩下的就轻松了。",
        "哈哈，这个主意不错！",
        "我一直在这里，想你的时候就戳戳小螃蟹吧。",
    ]

    public init() {}

    /// 发一条假消息：螃蟹先想一会儿，再横着写字，写完蹦一下举牌
    public func send(reply: String? = nil, withTool: Bool = false) {
        stop()
        let reply = reply ?? Self.sampleReplies.randomElement()!
        text = ""
        task = Task { [weak self] in
            guard let self else { return }
            state = .thinking
            if useIsland { IslandCrab.shared.start(title: "演示", style: style) }
            try? await Task.sleep(for: .seconds(1.6))
            if withTool {
                fire(.flower)
                if useIsland { IslandCrab.shared.set(.tool) }
                try? await Task.sleep(for: .seconds(2.4))
            }
            guard !Task.isCancelled else { return }
            state = .walking
            if useIsland { IslandCrab.shared.set(.writing) }
            for ch in reply {
                guard !Task.isCancelled else { return }
                text.append(ch)
                try? await Task.sleep(for: .milliseconds(70))
            }
            if CrabCue.isSweet(reply) { fire(.heart) }
            state = .happy
            if useIsland { IslandCrab.shared.finish() }
            CrabSnapshot(pose: "happy", voice: reply, style: style, updatedAt: .now).publish()
            try? await Task.sleep(for: .seconds(0.9))
            state = .idle
            fire(.sign(reply))
            task = nil
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        if state != .idle {
            state = .idle
            if useIsland { IslandCrab.shared.cancel() }
        }
    }

    /// 直接递一个暗号
    public func fire(_ kind: CrabCue.Kind) {
        serial += 1
        cue = CrabCue(kind: kind, serial: serial)
    }
}
