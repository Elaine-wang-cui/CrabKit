import SwiftUI
import UIKit

/// 代码块的简易高亮：关键字、字符串、注释、数字、类型、函数名。
/// 不追求每种语言都准，常见的 Swift、Python、JS/TS、Go、Rust、C 系、Shell、SQL 看着对就行。
enum CodeHighlighter {
    static let plain = Color(UIColor(hex: 0xE8E3DA))
    static let keyword = Color(UIColor(hex: 0xC9A0DC))
    static let string = Color(UIColor(hex: 0xABCB8F))
    static let comment = Color(UIColor(hex: 0x8C867C))
    static let number = Color(UIColor(hex: 0xE8A86E))
    static let type = Color(UIColor(hex: 0x80C2D6))
    static let function = Color(UIColor(hex: 0xEAD08A))

    private static let hashLangs: Set<String> = [
        "python", "py", "ruby", "rb", "sh", "bash", "zsh", "shell", "console", "yaml", "yml", "toml",
        "r", "perl", "pl", "makefile", "make", "dockerfile", "ps1", "powershell", "elixir", "ex", "nim",
        "coffee", "conf", "ini", "fish", "gitignore", "cmake"
    ]
    private static let dashLangs: Set<String> = ["sql", "lua", "haskell", "hs", "elm", "ada"]

    private static let keywords: Set<String> = [
        "let", "var", "func", "function", "def", "class", "struct", "enum", "protocol", "extension",
        "interface", "type", "return", "if", "else", "elif", "for", "while", "do", "in", "of", "switch",
        "case", "default", "break", "continue", "import", "from", "export", "as", "try", "catch", "throw",
        "throws", "rethrows", "finally", "async", "await", "guard", "self", "Self", "this", "super", "nil",
        "null", "None", "true", "false", "True", "False", "new", "public", "private", "fileprivate",
        "internal", "open", "static", "final", "override", "const", "mut", "fn", "impl", "pub", "use", "mod",
        "match", "where", "package", "go", "defer", "chan", "select", "yield", "lambda", "with", "pass",
        "raise", "except", "not", "and", "or", "is", "void", "int", "bool", "float", "double", "char",
        "long", "unsigned", "echo", "then", "fi", "done", "esac", "local", "some", "any", "inout", "init",
        "deinit", "get", "set", "willSet", "didSet", "mutating", "typealias", "associatedtype",
        "undefined", "typeof", "instanceof", "delete", "extends", "implements", "abstract", "readonly",
        "declare", "namespace", "module", "require", "end", "begin", "unless", "until", "elsif", "loop",
        "crate", "dyn", "ref", "move", "unsafe", "global", "nonlocal", "assert", "del", "print",
        "goto", "volatile", "extern", "sizeof", "union", "typedef", "auto", "register", "signed",
        "short", "byte", "boolean", "string", "number", "keyof", "satisfies", "debugger", "when",
        "val", "object", "companion", "data", "sealed", "fun", "lazy", "weak", "unowned",
        "convenience", "required", "optional", "indirect", "nonisolated", "actor", "isolated", "consume"
    ]
    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create",
        "table", "drop", "alter", "add", "join", "left", "right", "inner", "outer", "on", "group", "by",
        "order", "having", "limit", "offset", "as", "and", "or", "not", "null", "is", "in", "like",
        "distinct", "union", "all", "primary", "key", "foreign", "references", "index", "view", "case",
        "when", "then", "else", "end", "exists", "between", "asc", "desc", "count", "sum", "avg", "min", "max"
    ]

    static func highlight(_ code: String, language: String) -> AttributedString {
        let lang = language.lowercased()
        let usesHash = hashLangs.contains(lang)
        let usesDash = dashLangs.contains(lang)
        let isSQL = lang == "sql"
        let blockComments = !usesHash
        let chars = Array(code)
        let n = chars.count
        var out = AttributedString()
        var i = 0

        func emit(_ from: Int, _ to: Int, _ color: Color, italic: Bool = false) {
            guard to > from else { return }
            var piece = AttributedString(String(chars[from..<to]))
            piece.foregroundColor = color
            if italic { piece.font = .system(.footnote, design: .monospaced).italic() }
            out.append(piece)
        }
        func starts(_ s: String, at k: Int) -> Bool {
            let p = Array(s)
            guard k + p.count <= n else { return false }
            for j in 0..<p.count where chars[k + j] != p[j] { return false }
            return true
        }
        func endOfLine(_ k: Int) -> Int {
            var e = k
            while e < n && chars[e] != "\n" { e += 1 }
            return e
        }
        func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" || c == "$" }
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }
        func atLineStartOrSpace(_ k: Int) -> Bool { k == 0 || chars[k - 1] == "\n" || chars[k - 1] == " " || chars[k - 1] == "\t" }

        while i < n {
            let c = chars[i]

            // 行注释
            var lineComment = false
            if c == "#" {
                if usesHash {
                    lineComment = true
                } else if lang.isEmpty && atLineStartOrSpace(i) {
                    // 没写语言时，行首的「# 」也当注释
                    let after: Character = i + 1 < n ? chars[i + 1] : " "
                    lineComment = after == " " || after == "!"
                }
            } else if usesDash {
                lineComment = starts("--", at: i)
            } else if !usesHash {
                lineComment = starts("//", at: i)
            }
            if lineComment {
                let e = endOfLine(i)
                emit(i, e, comment, italic: true)
                i = e
                continue
            }
            // 块注释
            if blockComments && starts("/*", at: i) {
                var e = i + 2
                while e < n && !starts("*/", at: e) { e += 1 }
                e = min(n, e + 2)
                emit(i, e, comment, italic: true)
                i = e
                continue
            }
            // 三引号字符串
            if starts("\"\"\"", at: i) || starts("'''", at: i) {
                let q = String(repeating: String(c), count: 3)
                var e = i + 3
                while e < n && !starts(q, at: e) { e += 1 }
                e = min(n, e + 3)
                emit(i, e, string)
                i = e
                continue
            }
            // 普通字符串：同一行里找收尾的引号；反引号可以跨行
            if c == "\"" || c == "'" || c == "`" {
                var e = i + 1
                var closed = false
                while e < n {
                    if chars[e] == "\\" { e += 2; continue }
                    if chars[e] == c { closed = true; e += 1; break }
                    if chars[e] == "\n" && c != "`" { break }
                    e += 1
                }
                e = min(n, e)
                if !closed && c == "'" {
                    // Rust 的生命周期、英文里的撇号，别把后面整行染绿
                    emit(i, i + 1, plain)
                    i += 1
                } else {
                    emit(i, e, string)
                    i = e
                }
                continue
            }
            // 数字
            if c.isNumber && (i == 0 || !isIdent(chars[i - 1])) {
                var e = i + 1
                while e < n && (chars[e].isHexDigit || "xXoObB._".contains(chars[e])) { e += 1 }
                emit(i, e, number)
                i = e
                continue
            }
            // @注解、#宏
            if (c == "@" || (c == "#" && !usesHash)) && i + 1 < n && isIdentStart(chars[i + 1]) {
                var e = i + 1
                while e < n && isIdent(chars[e]) { e += 1 }
                emit(i, e, keyword)
                i = e
                continue
            }
            // 标识符
            if isIdentStart(c) {
                var e = i + 1
                while e < n && isIdent(chars[e]) { e += 1 }
                let word = String(chars[i..<e])
                var next = e
                while next < n && chars[next] == " " { next += 1 }
                let color: Color
                if keywords.contains(word) || (isSQL && sqlKeywords.contains(word.lowercased())) {
                    color = keyword
                } else if next < n && chars[next] == "(" {
                    color = function
                } else if let first = word.first, first.isUppercase {
                    color = type
                } else {
                    color = plain
                }
                emit(i, e, color)
                i = e
                continue
            }
            // 其他符号：连着的一串一起放
            var e = i + 1
            while e < n && !isIdent(chars[e]) && !"\"'`#/@-".contains(chars[e]) && !chars[e].isNumber { e += 1 }
            emit(i, e, plain)
            i = e
        }
        return out
    }
}
