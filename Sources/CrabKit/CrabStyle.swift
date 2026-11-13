import Foundation

/// 爱心钳子小螃蟹
public enum CrabStyle: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case heart

    public var id: String { rawValue }

    public var label: String { "爱心钳子" }

    /// 一帧有多少格宽，算位置用
    public var columns: Int { 28 }

    /// 这只一直正面横着走，不会转到侧身
    public var turnsSideways: Bool { false }
}
