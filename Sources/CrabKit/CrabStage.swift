import SwiftUI
import Observation

/// 小螃蟹的「舞台」：它能在哪块区域里活动、现在停在哪。
/// - area：能把它拎过去的范围（全屏坐标）。不设就只在自己那条线附近活动。
/// - handedOff：如果你有开场动画（比如一只螃蟹爬进来再交棒），开场时设成 false，
///   开场那只到位后再设回 true；没有开场动画就保持默认的 true。
@MainActor @Observable
public final class CrabStage {
    public static let shared = CrabStage()

    /// 对话页那只螃蟹现在的位置（全屏坐标）
    public var restFrame: CGRect = .zero
    /// 那只的像素大小
    public var restPixel: CGFloat = 10.0 / 3
    /// 开场的已经交棒；false 时会溜达的那只先藏着
    public var handedOff = true
    /// 可活动区域（全屏坐标）
    public var area: CGRect = .zero

    public init() {}
}
