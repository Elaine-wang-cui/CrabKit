import SwiftUI

/// 状态行拆开：名字、若干「标签 数字」、一个阈值、一个档位词。没有这些数字就不当成状态。
struct MoodStatus: Equatable {
    struct Metric: Equatable, Identifiable {
        var label: String
        var value: Double
        var id: String { label }
    }

    var name: String = ""
    var metrics: [Metric] = []
    var threshold: Double?
    var band: String = ""

    /// 平静 / 起了 / 硬着 / 快到了：行里写了就用写的，没写按兴奋算
    static let bands = ["平静", "起了", "硬着", "快到了"]

    static func band(for arousal: Double) -> String {
        switch arousal {
        case ..<30: "平静"
        case ..<60: "起了"
        case ..<80: "硬着"
        default: "快到了"
        }
    }

    /// 脸红：硬着或者更往上
    var blushing: Bool { band == "硬着" || band == "快到了" }

    var arousal: Double? { metrics.first { $0.label.contains("兴奋") }?.value }

    static func parse(_ raw: String?) -> MoodStatus? {
        guard let raw, !raw.isEmpty else { return nil }
        let separators = CharacterSet(charactersIn: "·・|｜•")
        let pieces = raw.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var out = MoodStatus()
        var loose: [String] = []
        for piece in pieces {
            if let (label, value) = labelAndNumber(piece) {
                if label.contains("阈值") {
                    out.threshold = value
                } else {
                    out.metrics.append(Metric(label: label, value: min(100, max(0, value))))
                }
            } else {
                loose.append(piece)
            }
        }
        guard !out.metrics.isEmpty else { return nil }
        // 没数字的段：写着档位的就是档位，其余第一个是名字
        for piece in loose {
            if out.band.isEmpty, bands.contains(where: { piece.contains($0) }) {
                out.band = piece
            } else if out.name.isEmpty {
                out.name = piece
            } else {
                out.band = piece
            }
        }
        if out.band.isEmpty, let a = out.arousal { out.band = band(for: a) }
        return out
    }

    /// 「兴奋 62」「兴奋:62」「兴奋62%」都认
    private static func labelAndNumber(_ s: String) -> (String, Double)? {
        let scalars = Array(s)
        guard let start = scalars.firstIndex(where: { $0.isASCII && $0.isNumber }) else { return nil }
        var end = start
        while end < scalars.count, (scalars[end].isASCII && scalars[end].isNumber) || scalars[end] == "." { end += 1 }
        guard let value = Double(String(scalars[start..<end])) else { return nil }
        let label = String(scalars[..<start]).trimmingCharacters(in: CharacterSet(charactersIn: " :：="))
        guard !label.isEmpty else { return nil }
        return (label, value)
    }
}

/// 最近一条回复的状态：螃蟹看它脸红，新仪表从上一条的数值滑过去
@MainActor @Observable
final class MoodMeter {
    static let shared = MoodMeter()
    var current: MoodStatus?
    var previous: MoodStatus?

    func update(_ status: MoodStatus?) {
        guard let status else { return }
        previous = current
        current = status
    }

    /// 打开一段旧对话时，从最后一条回复里读
    func load(from messages: [ChatMessage]) {
        previous = nil
        current = messages.last { $0.role == .assistant }
            .flatMap { MoodStatus.parse(InnerVoice.split($0.text).status) }
    }

    func reset() {
        previous = nil
        current = nil
    }
}

/// 回复下面的小仪表：名字、档位小胶囊，几根会滑动的小条
struct StatusDashboard: View {
    let status: MoodStatus
    /// 刚写完的：从上一条的数值滑到新的
    let animate: Bool
    @State private var shown: [String: Double] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !status.name.isEmpty {
                    Text(status.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                if !status.band.isEmpty {
                    Text(status.band)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(bandColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(bandColor.opacity(0.14), in: Capsule())
                }
                if let t = status.threshold {
                    Text("阈值 \(Int(t))")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .leading)],
                      alignment: .leading, spacing: 5) {
                ForEach(status.metrics) { m in
                    MeterBar(label: m.label,
                             value: shown[m.label] ?? m.value,
                             target: m.value,
                             color: Self.color(for: m.label),
                             threshold: m.label.contains("兴奋") ? status.threshold : nil)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border.opacity(0.5), lineWidth: 0.5))
        .frame(maxWidth: 340, alignment: .leading)
        .onAppear(perform: start)
        .onChange(of: status) { _, _ in start() }
    }

    private func start() {
        let previous = MoodMeter.shared.previous
        if animate, let previous {
            var from: [String: Double] = [:]
            for m in status.metrics {
                from[m.label] = previous.metrics.first { $0.label == m.label }?.value ?? 0
            }
            shown = from
            withAnimation(.spring(duration: 1.1, bounce: 0.2).delay(0.3)) {
                shown = Dictionary(status.metrics.map { ($0.label, $0.value) }, uniquingKeysWith: { _, b in b })
            }
        } else if animate {
            shown = Dictionary(status.metrics.map { ($0.label, 0.0) }, uniquingKeysWith: { _, b in b })
            withAnimation(.spring(duration: 1.1, bounce: 0.2).delay(0.3)) {
                shown = Dictionary(status.metrics.map { ($0.label, $0.value) }, uniquingKeysWith: { _, b in b })
            }
        } else {
            shown = [:]
        }
    }

    private var bandColor: Color {
        switch status.band {
        case let b where b.contains("快到"): Color(red: 0.86, green: 0.25, blue: 0.38)
        case let b where b.contains("硬"): Color(red: 0.93, green: 0.42, blue: 0.52)
        case let b where b.contains("起"): Theme.accent
        default: Theme.textSecondary
        }
    }

    static func color(for label: String) -> Color {
        if label.contains("兴奋") { return Theme.accent }
        if label.contains("敏感") { return Color(red: 0.93, green: 0.46, blue: 0.60) }
        if label.contains("麻木") { return Color(white: 0.6) }
        if label.contains("失落") { return Color(red: 0.45, green: 0.58, blue: 0.75) }
        if label.contains("难过") { return Color(red: 0.42, green: 0.42, blue: 0.78) }
        return Theme.textSecondary
    }
}

private struct MeterBar: View {
    let label: String
    let value: Double
    let target: Double
    let color: Color
    let threshold: Double?

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.border.opacity(0.6))
                    Capsule().fill(color).frame(width: max(0, g.size.width * value / 100))
                    if let threshold {
                        Rectangle()
                            .fill(Theme.textSecondary.opacity(0.6))
                            .frame(width: 1, height: g.size.height + 4)
                            .offset(x: g.size.width * min(threshold, 100) / 100 - 0.5)
                    }
                }
            }
            .frame(height: 5)
            Text("\(Int(target.rounded()))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
                .frame(minWidth: 16, alignment: .trailing)
        }
    }
}
