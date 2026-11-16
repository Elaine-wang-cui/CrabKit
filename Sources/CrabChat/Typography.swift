import SwiftUI
import UIKit
import CoreText

/// 读回复用的字体。宋体、楷体、圆体是 iOS 自带但要现下的系统字体，第一次选会下一下，之后直接用
enum ReadingFont: String, CaseIterable, Identifiable {
    case system, songti, kaiti, yuanti

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "PingFang"
        case .songti: "Song"
        case .kaiti: "Kai"
        case .yuanti: "Rounded"
        }
    }

    /// 要现下的那几个的系统名字
    var postScript: String? {
        switch self {
        case .system: nil
        case .songti: "STSongti-SC-Regular"
        case .kaiti: "STKaiti-SC-Regular"
        case .yuanti: "STYuanti-SC-Regular"
        }
    }

    /// 还没下好时先顶上的样子
    var fallbackDesign: Font.Design {
        switch self {
        case .system: .default
        case .songti, .kaiti: .serif
        case .yuanti: .rounded
        }
    }
}

/// 排版：字体、字号倍数、行距。整页通过环境往下传，设置页的预览也用同一套
struct ReadingStyle: Equatable {
    var font: ReadingFont = .system
    var scale: Double = 1
    var lineGap: Double = 4
    /// 字体下好了没有（变了界面要跟着换）
    var fontReady = false

    /// 跟着系统的大字设置一起缩放
    func size(_ base: CGFloat, _ style: UIFont.TextStyle = .body) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: base * scale)
    }

    func face(_ base: CGFloat, _ style: UIFont.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        let s = size(base, style)
        if fontReady, let ps = font.postScript {
            return .custom(ps, fixedSize: s).weight(weight)
        }
        return .system(size: s, weight: weight, design: font.fallbackDesign)
    }

    var body: Font { face(17) }
    var small: Font { face(15, .subheadline) }

    func heading(_ level: Int) -> Font {
        switch level {
        case 1: face(22, .title2, weight: .bold)
        case 2: face(20, .title3, weight: .bold)
        case 3: face(17, .headline, weight: .semibold)
        default: face(15, .subheadline, weight: .bold)
        }
    }
}

private struct ReadingStyleKey: EnvironmentKey {
    static let defaultValue = ReadingStyle()
}

extension EnvironmentValues {
    var reading: ReadingStyle {
        get { self[ReadingStyleKey.self] }
        set { self[ReadingStyleKey.self] = newValue }
    }
}

/// 现下系统字体。下过的每次开 app 还要「认领」一下，很快，不走网络
@MainActor @Observable
final class FontLoader {
    static let shared = FontLoader()

    private(set) var ready: Set<String> = []
    private(set) var progress: [String: Double] = [:]
    private(set) var failed: Set<String> = []
    private var loading: Set<String> = []

    func isReady(_ font: ReadingFont) -> Bool {
        guard let ps = font.postScript else { return true }
        return ready.contains(ps)
    }

    func ensure(_ font: ReadingFont) {
        guard let ps = font.postScript else { return }
        if UIFont(name: ps, size: 12) != nil {
            ready.insert(ps)
            return
        }
        guard !loading.contains(ps) else { return }
        loading.insert(ps)
        failed.remove(ps)
        progress[ps] = 0
        let attrs = [kCTFontNameAttribute as String: ps] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes(attrs)
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, info in
            let dict = info as NSDictionary
            switch state {
            case .downloading:
                let pct = (dict[kCTFontDescriptorMatchingPercentage as String] as? NSNumber)?.doubleValue ?? 0
                Task { @MainActor in FontLoader.shared.progress[ps] = pct / 100 }
            case .didFinish:
                Task { @MainActor in FontLoader.shared.finish(ps) }
            case .didFailWithError:
                Task { @MainActor in FontLoader.shared.fail(ps) }
            default:
                break
            }
            return true
        }
    }

    private func finish(_ ps: String) {
        loading.remove(ps)
        progress[ps] = nil
        if UIFont(name: ps, size: 12) != nil {
            ready.insert(ps)
        } else {
            failed.insert(ps)
        }
    }

    private func fail(_ ps: String) {
        loading.remove(ps)
        progress[ps] = nil
        failed.insert(ps)
    }
}
