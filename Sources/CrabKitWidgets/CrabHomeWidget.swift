import CrabKit
import SwiftUI
import WidgetKit

/// 桌面小组件：小螃蟹现在的样子和一句话（app 用 CrabSnapshot.publish() 更新）
public struct CrabHomeWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: CrabSnapshot.widgetKind, provider: CrabHomeProvider()) { entry in
            CrabHomeView(entry: entry)
        }
        .configurationDisplayName("小螃蟹")
        .description("小螃蟹现在的样子，和最近的一句话。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CrabHomeEntry: TimelineEntry {
    let date: Date
    let snap: CrabSnapshot
    /// 一直没有新回复、又是半夜，就让它犯困
    var drowsy: Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return (1...6).contains(hour) && date.timeIntervalSince(snap.updatedAt) > 3600
    }
    var shownSnap: CrabSnapshot {
        var s = snap
        if drowsy { s.pose = "sleepy" }
        return s
    }
}

struct CrabHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> CrabHomeEntry {
        CrabHomeEntry(date: .now, snap: CrabSnapshot(pose: "wave", voice: "今天也要开心呀"))
    }

    func getSnapshot(in context: Context, completion: @escaping (CrabHomeEntry) -> Void) {
        let snap = CrabSnapshot.read() ?? CrabSnapshot(pose: "wave", voice: context.isPreview ? "今天也要开心呀" : "")
        completion(CrabHomeEntry(date: .now, snap: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CrabHomeEntry>) -> Void) {
        let snap = CrabSnapshot.read() ?? CrabSnapshot(pose: "wave")
        // 回复写完 app 会叫它刷新；另外每小时自己看一眼，半夜好换成犯困
        let now = Date.now
        let entries = (0..<6).map { i in
            CrabHomeEntry(date: now.addingTimeInterval(Double(i) * 3600), snap: snap)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct CrabHomeView: View {
    let entry: CrabHomeEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private let accent = Color(red: 0.914, green: 0.439, blue: 0.310)
    private var paper: Color {
        scheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.14) : Color(red: 0.976, green: 0.973, blue: 0.965)
    }
    private var ink: Color {
        scheme == .dark ? Color(red: 0.93, green: 0.91, blue: 0.88) : Color(red: 0.12, green: 0.11, blue: 0.10)
    }
    private var faint: Color { ink.opacity(0.5) }

    private var snap: CrabSnapshot { entry.shownSnap }
    private var line: String {
        if entry.drowsy { return "zzz…" }
        return snap.voice.isEmpty ? "还没有新消息" : snap.voice
    }

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .containerBackground(for: .widget) { paper }
    }

    private func crab(_ size: CGFloat) -> some View {
        let pixel = size / CGFloat(snap.style.columns + 2)
        return PixelCrab(frame: snap.frame(), pixel: pixel)
    }

    private var small: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            crab(78)
            Spacer(minLength: 0)
            Text(line)
                .font(.caption.italic())
                .foregroundStyle(faint)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            crab(96)
                .frame(width: 104)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("小螃蟹说")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                    Spacer(minLength: 0)
                }
                Text(line)
                    .font(.subheadline.italic())
                    .foregroundStyle(ink.opacity(0.75))
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if snap.updatedAt > .distantPast {
                    Text(snap.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
