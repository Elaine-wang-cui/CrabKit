import Foundation

/// 记下用户对小螃蟹做了什么（戳、戳到害羞、戳醒、拎起来、拍扁）。
/// 想让聊天对象「知道」你怎么对小螃蟹，就在发下一条消息时调用 takeNote()，
/// 把返回的那句旁白悄悄带上；不需要就不用管它。
@MainActor
public final class CrabLog {
    public static let shared = CrabLog()

    public enum Kind: CaseIterable, Sendable {
        case poke, shy, wake, lift, squash
    }

    /// 每记一次都会回调，方便你自己统计或做别的
    public var onNote: ((Kind) -> Void)?

    private var counts: [Kind: Int] = [:]

    public init() {}

    public func note(_ kind: Kind) {
        counts[kind, default: 0] += 1
        onNote?(kind)
    }

    public func clear() {
        counts = [:]
    }

    /// 现在记了多少次
    public func count(_ kind: Kind) -> Int { counts[kind] ?? 0 }

    /// 拼成一句旁白，没有就返回 nil；拿完就清空
    public func takeNote() -> String? {
        defer { counts = [:] }
        var parts: [String] = []
        for kind in Kind.allCases {
            guard let n = counts[kind], n > 0 else { continue }
            parts.append(Self.phrase(kind, n))
        }
        guard !parts.isEmpty else { return nil }
        return "［app 旁白，不是用户打的字：界面里住着一只像素小螃蟹。用户刚才" + parts.joined(separator: "，") + "。］"
    }

    private static func phrase(_ kind: Kind, _ n: Int) -> String {
        let times = n > 1 ? " \(n) 次" : ""
        switch kind {
        case .poke: return "戳了它 \(n) 下"
        case .shy: return "把它戳害羞了" + times
        case .wake: return "把睡着的它戳醒了" + times
        case .lift: return "把它拎起来拖走" + times
        case .squash: return "把它拍扁了" + times
        }
    }
}
