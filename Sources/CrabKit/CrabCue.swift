import Foundation

/// 外面（比如聊天界面）递给螃蟹的一次性小暗号。serial 每次都要不一样，同一种暗号连着来也能触发。
public struct CrabCue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 冒小爱心（比如回复里出现了甜甜的词）
        case heart
        /// 抱着小花跑一圈（比如正在调用工具、翻资料）
        case flower
        /// 学你贴的表情做同款
        case reaction(String)
        /// 举起小木牌，头顶冒泡念一句话
        case sign(String)
    }

    public let kind: Kind
    public let serial: Int

    public init(kind: Kind, serial: Int) {
        self.kind = kind
        self.serial = serial
    }

    /// 文字里出现这些词就可以给螃蟹递 .heart。可以在启动时换成你自己的词。
    public static var sweetWords = ["爱你", "想你", "喜欢你", "抱抱", "love you", "miss you"]

    /// 支持学样的表情
    public static let reactions = ["❤️", "😂", "👍", "😭", "😳", "🥺"]

    /// 这段文字里有没有甜甜的词
    public static func isSweet(_ text: String) -> Bool {
        sweetWords.contains { text.localizedCaseInsensitiveContains($0) }
    }
}

/// 一天里的几个时段：螃蟹的心情和问候语跟着变
public enum TimeOfDay: Equatable, Sendable {
    case lateNight, morning, noon, afternoon, evening

    public static var now: TimeOfDay {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<10: .morning
        case 10..<14: .noon
        case 14..<18: .afternoon
        case 18..<23: .evening
        default: .lateNight
        }
    }

    private var greetings: [String] {
        switch self {
        case .lateNight: ["还没睡呀", "夜猫子时间", "这么晚啦"]
        case .morning: ["早上好", "早安", "新的一天"]
        case .noon: ["中午好", "该吃午饭啦"]
        case .afternoon: ["下午好", "喝杯茶吧"]
        case .evening: ["晚上好", "欢迎回来"]
        }
    }

    /// 同一天里问候语不变，换一天换一句
    public var greeting: String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return greetings[day % greetings.count]
    }
}
