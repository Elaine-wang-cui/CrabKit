import ActivityKit
import Foundation

/// 灵动岛里那只小螃蟹的实时活动数据。app 开始干活时启动，干完显示开心再收起。
/// app 和小组件扩展两边都要 import CrabKit，用的是同一个类型。
public struct CrabActivityAttributes: ActivityAttributes {
    public enum Phase: String, Codable, Hashable, Sendable {
        case thinking, writing, tool, done

        public var label: String {
            switch self {
            case .thinking: "思考中"
            case .writing: "写字中"
            case .tool: "找东西中"
            case .done: "写好啦"
            }
        }

        public func frames(_ style: CrabStyle) -> [CrabFrame] {
            switch self {
            case .thinking: HeartCrabSprites.thinking
            case .writing: HeartCrabSprites.walking
            case .done: HeartCrabSprites.happy
            case .tool: HeartCrabSprites.flowerRun
            }
        }
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: Phase
        /// app 每隔一小会儿加一，灵动岛按它换帧
        public var frame: Int

        public init(phase: Phase, frame: Int) {
            self.phase = phase
            self.frame = frame
        }

        public func crabFrame(_ style: CrabStyle) -> CrabFrame {
            let frames = phase.frames(style)
            return frames[abs(frame) % frames.count]
        }
    }

    /// 展开时显示的一行小字（比如任务名、模型名），可以留空
    public var title: String
    /// 小螃蟹的样式
    public var style: CrabStyle

    public init(title: String, style: CrabStyle) {
        self.title = title
        self.style = style
    }
}
