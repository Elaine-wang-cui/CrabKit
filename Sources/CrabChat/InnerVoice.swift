import Foundation

/// 回复末尾的心声：最后一行 `行内代码`，前面可能还有一行〔状态行〕。
/// 只在显示时拆出来；存下的原文不动，下一轮照原样发回去，模型才记得这个格式。
enum InnerVoice {
    struct Parts: Equatable {
        var body: String
        var status: String?
        var voice: String?
        var isEmpty: Bool { status == nil && voice == nil }
    }

    static func split(_ text: String, live: Bool = false) -> Parts {
        var lines = text.components(separatedBy: "\n")
        func dropBlankTail() {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        }
        dropBlankTail()

        // 还在写的时候，末尾那行刚冒出个 ` 或〔，先藏起来，免得闪一下
        if live {
            for _ in 0..<2 {
                guard let last = lines.last?.trimmingCharacters(in: .whitespaces) else { break }
                if last.hasPrefix("`") || last.hasPrefix("〔") {
                    lines.removeLast()
                    dropBlankTail()
                } else {
                    break
                }
            }
            return Parts(body: lines.joined(separator: "\n"), status: nil, voice: nil)
        }

        var status: String?
        var voice: String?
        // 两行谁先谁后都认
        for _ in 0..<2 {
            guard let last = lines.last?.trimmingCharacters(in: .whitespaces) else { break }
            if voice == nil, let v = codeLine(last) {
                voice = v
            } else if status == nil, last.hasPrefix("〔"), last.hasSuffix("〕"), last.count > 2 {
                status = String(last.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            } else {
                break
            }
            lines.removeLast()
            dropBlankTail()
        }
        return Parts(body: lines.joined(separator: "\n"), status: status, voice: voice)
    }

    /// 整行就是一段 `...`
    private static func codeLine(_ line: String) -> String? {
        guard line.count > 2, line.hasPrefix("`"), line.hasSuffix("`"), !line.hasPrefix("```") else { return nil }
        let inner = line.dropFirst().dropLast()
        guard !inner.contains("`") else { return nil }
        let t = inner.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
