import SwiftUI

/// LaTeX 的一棵小树：够用来排常见的公式（分数、根号、上下标、求和积分、希腊字母和运算符）
indirect enum MathNode {
    case symbol(String, italic: Bool)
    case row([MathNode])
    case frac(MathNode, MathNode)
    case sqrt(MathNode)
    case scripts(MathNode, sup: MathNode?, sub: MathNode?)
    case bigOp(String, sup: MathNode?, sub: MathNode?)
    case newline
}

enum LaTeX {
    static let symbols: [String: String] = [
        // 希腊字母
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο", "pi": "π", "varpi": "ϖ",
        "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ",
        "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
        "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // 运算和关系
        "times": " × ", "cdot": " · ", "div": " ÷ ", "pm": " ± ", "mp": " ∓ ", "ast": "∗", "star": "⋆",
        "circ": "∘", "bullet": "•", "oplus": " ⊕ ", "otimes": " ⊗ ",
        "leq": " ≤ ", "le": " ≤ ", "geq": " ≥ ", "ge": " ≥ ", "neq": " ≠ ", "ne": " ≠ ",
        "approx": " ≈ ", "equiv": " ≡ ", "sim": " ∼ ", "simeq": " ≃ ", "cong": " ≅ ", "propto": " ∝ ",
        "ll": " ≪ ", "gg": " ≫ ", "prec": " ≺ ", "succ": " ≻ ",
        "in": " ∈ ", "notin": " ∉ ", "ni": " ∋ ", "subset": " ⊂ ", "subseteq": " ⊆ ", "supset": " ⊃ ",
        "supseteq": " ⊇ ", "cup": " ∪ ", "cap": " ∩ ", "setminus": " ∖ ", "emptyset": "∅", "varnothing": "∅",
        "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "lnot": "¬", "land": " ∧ ", "wedge": " ∧ ",
        "lor": " ∨ ", "vee": " ∨ ",
        "to": " → ", "rightarrow": " → ", "leftarrow": " ← ", "gets": " ← ", "Rightarrow": " ⇒ ",
        "Leftarrow": " ⇐ ", "leftrightarrow": " ↔ ", "Leftrightarrow": " ⇔ ", "iff": " ⇔ ",
        "implies": " ⇒ ", "mapsto": " ↦ ", "longrightarrow": " ⟶ ", "uparrow": "↑", "downarrow": "↓",
        // 其他
        "infty": "∞", "partial": "∂", "nabla": "∇", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ",
        "aleph": "ℵ", "angle": "∠", "perp": " ⊥ ", "parallel": " ∥ ", "mid": " ∣ ", "degree": "°",
        "prime": "′", "cdots": "⋯", "ldots": "…", "dots": "…", "vdots": "⋮", "ddots": "⋱",
        "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉",
        "lvert": "|", "rvert": "|", "vert": "|", "Vert": "‖", "lbrace": "{", "rbrace": "}",
        "quad": "  ", "qquad": "    ", "therefore": "∴", "because": "∵", "checkmark": "✓",
        "triangle": "△", "square": "□", "top": "⊤", "bot": "⊥",
    ]

    static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
        "log", "ln", "lg", "exp", "lim", "max", "min", "sup", "inf", "det", "arg", "deg", "gcd", "dim",
        "ker", "hom", "Pr", "mod", "argmax", "argmin", "limsup", "liminf",
    ]

    /// 只取花括号里的字
    static let textCommands: Set<String> = [
        "text", "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "operatorname", "textbf", "textit",
        "textrm", "mbox", "mathcal", "mathscr", "mathfrak", "boldsymbol", "bm",
    ]

    /// 包一层但不画任何东西
    static let wrappers: Set<String> = [
        "overline", "underline", "bar", "hat", "widehat", "vec", "tilde", "widetilde", "dot", "ddot",
        "overrightarrow", "displaystyle", "textstyle", "boxed", "color",
    ]

    static let ignored: Set<String> = [
        "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "biggl", "biggr",
        "limits", "nolimits", "middle",
    ]

    static let bigOps: [String: String] = [
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮",
        "bigcup": "⋃", "bigcap": "⋂", "bigoplus": "⨁", "bigotimes": "⨂",
    ]

    static let blackboard: [Character: String] = [
        "R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ", "H": "ℍ", "E": "𝔼", "F": "𝔽", "1": "𝟙",
    ]

    static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "a": "ᵃ", "b": "ᵇ",
        "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ",
        "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ",
        "z": "ᶻ", "T": "ᵀ", "′": "′",
    ]

    static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ",
        "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ",
        "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]

    /// 行内公式：排成一行 Unicode，放进段落里
    static func inline(_ latex: String) -> String {
        var s = unicode(MathParser.parse(latex))
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func unicode(_ node: MathNode) -> String {
        switch node {
        case .symbol(let s, _):
            return s
        case .row(let items):
            return items.map { LaTeX.unicode($0) }.joined()
        case .frac(let a, let b):
            return wrap(unicode(a)) + "/" + wrap(unicode(b))
        case .sqrt(let a):
            let x = unicode(a).trimmingCharacters(in: .whitespaces)
            return "√" + (x.count > 1 ? "(\(x))" : x)
        case .scripts(let base, let sup, let sub):
            return unicode(base) + scriptText(sub, map: subscripts, mark: "_") + scriptText(sup, map: superscripts, mark: "^")
        case .bigOp(let glyph, let sup, let sub):
            return glyph + scriptText(sub, map: subscripts, mark: "_") + scriptText(sup, map: superscripts, mark: "^") + " "
        case .newline:
            return "  "
        }
    }

    private static func wrap(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.count <= 1 || s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." }) { return s }
        return "(\(s))"
    }

    private static func scriptText(_ node: MathNode?, map: [Character: Character], mark: String) -> String {
        guard let node else { return "" }
        let t = unicode(node).filter { $0 != " " }
        guard !t.isEmpty else { return "" }
        let mapped = t.compactMap { map[$0] }
        if mapped.count == t.count { return String(mapped) }
        return mark + (t.count == 1 ? t : "(\(t))")
    }
}

/// 把 LaTeX 字符串读成 MathNode。读不懂的命令原样当字显示，不会卡住
struct MathParser {
    private let chars: [Character]
    private var i = 0

    private init(_ s: String) { chars = Array(s) }

    static func parse(_ s: String) -> MathNode {
        var p = MathParser(s)
        return .row(p.parseRow(closing: nil))
    }

    private mutating func parseRow(closing: Character?) -> [MathNode] {
        var out: [MathNode] = []
        while i < chars.count {
            let c = chars[i]
            if let closing, c == closing {
                i += 1
                return out
            }
            if c == "^" || c == "_" {
                i += 1
                let arg = parseArgument()
                let base = out.popLast() ?? .symbol("", italic: false)
                out.append(Self.attach(arg, to: base, sup: c == "^"))
                continue
            }
            if let atom = parseAtom() { out.append(atom) }
        }
        return out
    }

    private static func attach(_ arg: MathNode, to base: MathNode, sup: Bool) -> MathNode {
        switch base {
        case .scripts(let b, let s, let d):
            return sup ? .scripts(b, sup: arg, sub: d) : .scripts(b, sup: s, sub: arg)
        case .bigOp(let g, let s, let d):
            return sup ? .bigOp(g, sup: arg, sub: d) : .bigOp(g, sup: s, sub: arg)
        default:
            return sup ? .scripts(base, sup: arg, sub: nil) : .scripts(base, sup: nil, sub: arg)
        }
    }

    private mutating func skipSpaces() {
        while i < chars.count, chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
    }

    /// ^ _ \frac 后面跟的一项：花括号一组，或者一个字、一个命令
    private mutating func parseArgument() -> MathNode {
        skipSpaces()
        guard i < chars.count else { return .symbol("", italic: false) }
        if chars[i] == "{" {
            i += 1
            return .row(parseRow(closing: "}"))
        }
        return parseAtom() ?? .symbol("", italic: false)
    }

    /// 花括号里的原文（\text{...} 用）
    private mutating func readRawGroup() -> String {
        skipSpaces()
        guard i < chars.count else { return "" }
        guard chars[i] == "{" else {
            let c = chars[i]
            i += 1
            return String(c)
        }
        i += 1
        var depth = 1
        var out = ""
        while i < chars.count {
            let c = chars[i]
            i += 1
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            if c != "\\" { out.append(c) }
        }
        return out
    }

    private mutating func parseAtom() -> MathNode? {
        let c = chars[i]
        switch c {
        case "{":
            i += 1
            return .row(parseRow(closing: "}"))
        case "}":
            i += 1
            return nil
        case "\\":
            return parseCommand()
        case " ", "\n", "\t":
            i += 1
            return nil
        case "~":
            i += 1
            return .symbol(" ", italic: false)
        case "&":
            i += 1
            return .symbol("  ", italic: false)
        case "-":
            i += 1
            return .symbol(" − ", italic: false)
        case "+", "=", "<", ">":
            i += 1
            return .symbol(" \(c) ", italic: false)
        case ",":
            i += 1
            return .symbol(", ", italic: false)
        case "'":
            i += 1
            return .symbol("′", italic: false)
        default:
            i += 1
            return .symbol(String(c), italic: c.isLetter)
        }
    }

    private mutating func parseCommand() -> MathNode? {
        i += 1
        guard i < chars.count else { return nil }
        let first = chars[i]
        if !first.isLetter {
            i += 1
            switch first {
            case "\\": return .newline
            case ",", ":", ">", " ": return .symbol(" ", italic: false)
            case ";": return .symbol("  ", italic: false)
            case "!": return nil
            case "|": return .symbol("‖", italic: false)
            default: return .symbol(String(first), italic: false)
            }
        }
        var name = ""
        while i < chars.count, chars[i].isLetter {
            name.append(chars[i])
            i += 1
        }
        switch name {
        case "frac", "dfrac", "tfrac", "cfrac":
            let a = parseArgument()
            let b = parseArgument()
            return .frac(a, b)
        case "binom", "dbinom", "tbinom":
            let a = parseArgument()
            let b = parseArgument()
            return .row([.symbol("(", italic: false), .frac(a, b), .symbol(")", italic: false)])
        case "sqrt":
            skipSpaces()
            if i < chars.count, chars[i] == "[" {
                // 几次根：把次数写成左上角的小字
                var index = ""
                i += 1
                while i < chars.count, chars[i] != "]" {
                    index.append(chars[i])
                    i += 1
                }
                i = min(i + 1, chars.count)
                let body = parseArgument()
                return .row([.scripts(.symbol("", italic: false), sup: .symbol(index, italic: false), sub: nil), .sqrt(body)])
            }
            return .sqrt(parseArgument())
        case "mathbb":
            let raw = readRawGroup()
            return .symbol(raw.map { LaTeX.blackboard[$0] ?? String($0) }.joined(), italic: false)
        case "begin", "end":
            _ = readRawGroup()
            return nil
        case "color":
            _ = readRawGroup()
            return nil
        default:
            if LaTeX.textCommands.contains(name) {
                return .symbol(readRawGroup(), italic: false)
            }
            if LaTeX.wrappers.contains(name) {
                return parseArgument()
            }
            if LaTeX.ignored.contains(name) {
                // \left. 和 \right. 的点不显示
                skipSpaces()
                if i < chars.count, chars[i] == "." { i += 1 }
                return nil
            }
            if let op = LaTeX.bigOps[name] { return .bigOp(op, sup: nil, sub: nil) }
            if LaTeX.functions.contains(name) { return .symbol(name + "\u{2009}", italic: false) }
            if let s = LaTeX.symbols[name] { return .symbol(s, italic: false) }
            return .symbol(name, italic: false)
        }
    }
}

/// 单独一行的公式：分数上下摞、根号带横线、上下标缩小，居中摆
struct MathView: View {
    let latex: String
    var size: CGFloat = 19

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                MathRender.view(line, size)
            }
        }
    }

    private var lines: [MathNode] {
        guard case .row(let items) = MathParser.parse(latex) else { return [] }
        var out: [MathNode] = []
        var current: [MathNode] = []
        for item in items {
            if case .newline = item {
                out.append(.row(current))
                current = []
            } else {
                current.append(item)
            }
        }
        if !current.isEmpty || out.isEmpty { out.append(.row(current)) }
        return out
    }
}

enum MathRender {
    static func view(_ node: MathNode, _ size: CGFloat) -> AnyView {
        let rule = max(1, size / 18)
        switch node {
        case .symbol(let s, let italic):
            return AnyView(
                Text(s)
                    .font(.system(size: size, design: .serif))
                    .italic(italic)
            )
        case .row(let items):
            return AnyView(
                HStack(alignment: .center, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, n in
                        MathRender.view(n, size)
                    }
                }
            )
        case .frac(let a, let b):
            return AnyView(
                Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                    GridRow { MathRender.view(a, size * 0.85) }
                    GridRow {
                        Rectangle()
                            .frame(height: rule)
                            .gridCellUnsizedAxes(.horizontal)
                    }
                    GridRow { MathRender.view(b, size * 0.85) }
                }
                .padding(.horizontal, 3)
            )
        case .sqrt(let a):
            return AnyView(
                HStack(alignment: .center, spacing: 0) {
                    Text("√")
                        .font(.system(size: size * 1.15, design: .serif))
                    MathRender.view(a, size)
                        .padding(.top, 3)
                        .padding(.trailing, 1)
                        .overlay(alignment: .top) {
                            Rectangle().frame(height: rule)
                        }
                }
            )
        case .scripts(let base, let sup, let sub):
            return AnyView(
                HStack(alignment: .center, spacing: 1) {
                    MathRender.view(base, size)
                    VStack(alignment: .leading, spacing: size * 0.15) {
                        if let sup {
                            MathRender.view(sup, size * 0.62)
                        } else {
                            Color.clear.frame(width: 1, height: size * 0.4)
                        }
                        if let sub {
                            MathRender.view(sub, size * 0.62)
                        } else {
                            Color.clear.frame(width: 1, height: size * 0.4)
                        }
                    }
                }
            )
        case .bigOp(let glyph, let sup, let sub):
            return AnyView(
                VStack(spacing: 0) {
                    if let sup { MathRender.view(sup, size * 0.6) }
                    Text(glyph)
                        .font(.system(size: size * 1.5, design: .serif))
                    if let sub { MathRender.view(sub, size * 0.6) }
                }
                .padding(.horizontal, 3)
            )
        case .newline:
            return AnyView(EmptyView())
        }
    }
}

/// 段落里的行内公式：$...$ 和 \(...\)
enum InlineMath {
    struct Piece {
        let text: String
        let isMath: Bool
    }

    static func split(_ s: String) -> [Piece] {
        guard s.contains("$") || s.contains("\\(") else { return [Piece(text: s, isMath: false)] }
        let chars = Array(s)
        var out: [Piece] = []
        var buf = ""
        var i = 0

        func flush() {
            if !buf.isEmpty { out.append(Piece(text: buf, isMath: false)) }
            buf = ""
        }

        while i < chars.count {
            let c = chars[i]
            // \( ... \)
            if c == "\\", i + 1 < chars.count, chars[i + 1] == "(" {
                var j = i + 2
                while j + 1 < chars.count, !(chars[j] == "\\" && chars[j + 1] == ")") { j += 1 }
                if j + 1 < chars.count {
                    flush()
                    out.append(Piece(text: String(chars[(i + 2)..<j]), isMath: true))
                    i = j + 2
                    continue
                }
            }
            // $...$：开头后面不能是空格或 $，收尾前面不能是空格，收尾后面不能紧跟数字（免得把 $5 和 $10 当公式）
            if c == "$", i == 0 || chars[i - 1] != "\\", i + 1 < chars.count, chars[i + 1] != "$", chars[i + 1] != " " {
                var j = i + 1
                var found = false
                while j < chars.count, chars[j] != "\n" {
                    if chars[j] == "$" && chars[j - 1] != " " && chars[j - 1] != "\\" {
                        found = true
                        break
                    }
                    j += 1
                }
                let followedByDigit = found && j + 1 < chars.count && chars[j + 1].isNumber
                if found && !followedByDigit {
                    flush()
                    out.append(Piece(text: String(chars[(i + 1)..<j]), isMath: true))
                    i = j + 1
                    continue
                }
            }
            buf.append(c)
            i += 1
        }
        flush()
        return out
    }
}
