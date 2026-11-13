import Foundation
import WidgetKit

/// app 写、桌面小组件读：小螃蟹现在的样子和一句话。
/// 两边靠同一个 App Group 共享。用之前先把 appGroup 改成你自己的（app 和小组件扩展里都要设）。
/// 没开 App Group 的话小组件读不到，就显示默认的样子。
public struct CrabSnapshot: Codable, Equatable, Sendable {
    /// 姿势：idle / happy / shy / laugh / cry / sleepy / wave
    public var pose: String
    /// 显示的那句话
    public var voice: String
    public var style: CrabStyle
    public var updatedAt: Date

    public init(pose: String = "idle", voice: String = "", style: CrabStyle = .heart, updatedAt: Date = .distantPast) {
        self.pose = pose
        self.voice = voice
        self.style = style
        self.updatedAt = updatedAt
    }

    /// 换成你自己的 App Group，例如 "group.com.yourname.crab"
    public static var appGroup = "group.com.example.crabkit"
    public static let widgetKind = "CrabHome"
    private static let key = "crab_snapshot"

    private static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func read() -> CrabSnapshot? {
        guard let data = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CrabSnapshot.self, from: data)
    }

    public func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.store?.set(data, forKey: Self.key)
    }

    /// 写进去并让桌面小组件刷新
    public func publish() {
        write()
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }

    /// 这个姿势的一帧（取中间那帧，表情最到位）
    public func frame() -> CrabFrame {
        let frames = Self.frames(pose, style)
        return frames[frames.count / 2]
    }

    private static func frames(_ pose: String, _ style: CrabStyle) -> [CrabFrame] {
        switch pose {
        case "happy": HeartCrabSprites.happy
        case "shy": HeartCrabSprites.shy
        case "laugh": HeartCrabSprites.laugh
        case "cry": HeartCrabSprites.cry
        case "sleepy": HeartCrabSprites.sleepy
        case "wave": HeartCrabSprites.wave
        default: HeartCrabSprites.idle
        }
    }
}
