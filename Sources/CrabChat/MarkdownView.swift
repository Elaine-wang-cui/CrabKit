import SwiftUI
import UIKit

/// 轻量 Markdown：标题、列表、引用、表格、分割线、代码块、数学公式，行内用系统 AttributedString。
struct MarkdownView: View {
    let text: String
    /// 流式写的时候，每冒出新的一段就淡入；翻历史记录时直接显示
    var fadeIn: Bool = false
    /// 铺满整行；气泡样式里关掉，让气泡跟着字的宽度走
    var fillsWidth: Bool = true
    @Environment(\.reading) private var reading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
                    .modifier(FadeInOnAppear(enabled: fadeIn))
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MDBlock) -> some View {
        switch block {
        case .paragraph(let s):
            MarkdownInline.text(s).font(reading.body).lineSpacing(reading.lineGap)
        case .heading(let level, let s):
            MarkdownInline.text(s)
                .font(reading.heading(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.textSecondary)
                        MarkdownInline.text(item).font(reading.body).lineSpacing(max(0, reading.lineGap - 1))
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(Theme.textSecondary)
                        MarkdownInline.text(item).font(reading.body).lineSpacing(max(0, reading.lineGap - 1))
                    }
                }
            }
        case .quote(let s):
            // 引用：往里缩一点，左边一根细细的暖色竖条
            MarkdownInline.text(s)
                .font(reading.body)
                .lineSpacing(reading.lineGap)
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 3)
                .padding(.leading, 16)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.accent.opacity(0.45)).frame(width: 2.5)
                        .padding(.leading, 2)
                }
        case .rule:
            Divider().padding(.vertical, 4)
        case .code(let lang, let code):
            CodeBlockView(language: lang, code: code)
        case .table(let header, let aligns, let rows):
            TableBlock(header: header, aligns: aligns, rows: rows)
        case .math(let tex):
            ViewThatFits(in: .horizontal) {
                MathView(latex: tex)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                ScrollView(.horizontal, showsIndicators: false) {
                    MathView(latex: tex)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                }
            }
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.bold()
        }
    }
}

/// 行内：粗体、斜体、行内代码、链接交给系统，$公式$ 换成排好的 Unicode
enum MarkdownInline {
    static func text(_ s: String) -> Text {
        let pieces = InlineMath.split(s)
        if pieces.count == 1, let only = pieces.first, !only.isMath { return markdown(s) }
        var out = Text(verbatim: "")
        for piece in pieces {
            out = out + (piece.isMath ? Text(LaTeX.inline(piece.text)).italic() : markdown(piece.text))
        }
        return out
    }

    private static func markdown(_ s: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: s, options: options) {
            return Text(attr)
        }
        return Text(s)
    }
}

/// 表格：表头灰底加粗，行之间细线，外面一圈圆角边
struct TableBlock: View {
    let header: [String]
    let aligns: [TableAlign]
    let rows: [[String]]

    private var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columns, id: \.self) { c in
                    cell(c < header.count ? header[c] : "", column: c, isHeader: true)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        cell(c < row.count ? row[c] : "", column: c, isHeader: false)
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func cell(_ s: String, column: Int, isHeader: Bool) -> some View {
        let align = column < aligns.count ? aligns[column] : .leading
        return MarkdownInline.text(s)
            .font(isHeader ? .subheadline.weight(.semibold) : .subheadline)
            .multilineTextAlignment(align.textAlignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align.frameAlignment)
            .background(isHeader ? Theme.thinkingBar : Color.clear)
    }
}

enum TableAlign {
    case leading, center, trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading: .topLeading
        case .center: .top
        case .trailing: .topTrailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// 新的一段出现时从透明淡入、轻轻往上浮一点
private struct FadeInOnAppear: ViewModifier {
    let enabled: Bool
    @State private var shown = false
    private let drift = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let visible = !enabled || shown
        // 飘进来：从下面一点点浮上来，带一点虚，落定时变清楚
        let floaty = drift && !reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : (floaty ? 14 : 6))
            .blur(radius: visible || !floaty ? 0 : 5)
            .scaleEffect(visible || !floaty ? 1 : 0.985, anchor: .topLeading)
            .onAppear {
                guard enabled, !shown else { return }
                if floaty {
                    withAnimation(.spring(duration: 0.9, bounce: 0.12)) { shown = true }
                } else {
                    withAnimation(.easeOut(duration: 0.5)) { shown = true }
                }
            }
    }
}

/// 代码块：深色底、语法高亮，右上角一键复制
struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    private static let headerText = Color(UIColor(hex: 0xA39C92))

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language.lowercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(Self.headerText)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    Haptics.copied()
                    withAnimation(.snappy) { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.snappy) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.caption)
                    .foregroundStyle(Self.headerText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy code")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 5)
            .background(Theme.codeHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(code, language: language))
                    .font(.system(.footnote, design: .monospaced))
                    .lineSpacing(3)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Theme.codeDark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum MDBlock {
    case paragraph(String)
    case heading(Int, String)
    case bullet([String])
    case numbered([String])
    case quote(String)
    case rule
    case code(String, String)
    case table([String], [TableAlign], [[String]])
    case math(String)
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var para: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var quote: [String] = []
        var table: [String] = []
        var inCode = false
        var codeLang = ""
        var code: [String] = []
        var inMath = false
        var mathEnd = "$$"
        var math: [String] = []

        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
            if !bullets.isEmpty { blocks.append(.bullet(bullets)); bullets = [] }
            if !numbers.isEmpty { blocks.append(.numbered(numbers)); numbers = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
            if !table.isEmpty {
                let cells = table.map { MarkdownParser.splitRow($0) }
                if cells.count >= 2, MarkdownParser.isSeparator(table[1]) {
                    blocks.append(.table(cells[0], cells[1].map { MarkdownParser.alignment($0) }, Array(cells.dropFirst(2))))
                } else {
                    // 流式时只来了表头，先当普通字
                    blocks.append(.paragraph(table.joined(separator: "\n")))
                }
                table = []
            }
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inMath && trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLang, code.joined(separator: "\n")))
                    inCode = false; code = []
                } else {
                    flush()
                    inCode = true
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            if inCode { code.append(line); continue }

            // 公式块：$$ ... $$ 或 \[ ... \]，可以一行也可以多行
            if inMath {
                if let r = trimmed.range(of: mathEnd) {
                    let head = String(trimmed[..<r.lowerBound])
                    if !head.isEmpty { math.append(head) }
                    blocks.append(.math(math.joined(separator: "\n")))
                    inMath = false; math = []
                } else {
                    math.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("$$") || trimmed.hasPrefix("\\[") {
                flush()
                let close = trimmed.hasPrefix("$$") ? "$$" : "\\]"
                let rest = String(trimmed.dropFirst(2))
                if let r = rest.range(of: close) {
                    blocks.append(.math(String(rest[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)))
                } else {
                    inMath = true
                    mathEnd = close
                    let head = rest.trimmingCharacters(in: .whitespaces)
                    if !head.isEmpty { math.append(head) }
                }
                continue
            }

            // 表格：连续的 | 开头的行
            if trimmed.hasPrefix("|") {
                if !para.isEmpty || !bullets.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
                table.append(trimmed)
                continue
            }
            if !table.isEmpty { flush() }

            if trimmed.isEmpty { flush(); continue }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { flush(); blocks.append(.rule); continue }
            if let h = heading(trimmed) { flush(); blocks.append(.heading(h.0, h.1)); continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                if !para.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
                bullets.append(String(trimmed.dropFirst(2)))
                continue
            }
            if let item = numberedItem(trimmed) {
                if !bullets.isEmpty || !para.isEmpty || !quote.isEmpty { flush() }
                numbers.append(item)
                continue
            }
            if trimmed.hasPrefix(">") {
                if !bullets.isEmpty || !para.isEmpty || !numbers.isEmpty { flush() }
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if !bullets.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
            para.append(line)
        }
        if inCode { blocks.append(.code(codeLang, code.joined(separator: "\n"))) }  // 流式时还没收尾的代码块
        if inMath { blocks.append(.math(math.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    private static func heading(_ s: String) -> (Int, String)? {
        for level in (1...6).reversed() {
            let prefix = String(repeating: "#", count: level) + " "
            if s.hasPrefix(prefix) { return (level, String(s.dropFirst(prefix.count))) }
        }
        return nil
    }

    private static func numberedItem(_ s: String) -> String? {
        guard let dot = s.firstIndex(of: "."), dot > s.startIndex,
              s[s.startIndex..<dot].allSatisfy(\.isNumber),
              s.index(after: dot) < s.endIndex, s[s.index(after: dot)] == " " else { return nil }
        return String(s[s.index(dot, offsetBy: 2)...])
    }

    private static func splitRow(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparator(_ line: String) -> Bool {
        line.contains("-") && line.allSatisfy { "|-: ".contains($0) }
    }

    private static func alignment(_ cell: String) -> TableAlign {
        let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
        if left && right { return .center }
        if right { return .trailing }
        return .leading
    }
}
