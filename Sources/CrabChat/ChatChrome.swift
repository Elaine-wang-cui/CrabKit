import Observation

/// How a reply is laid out.
enum ReplyStyle: String, CaseIterable, Identifiable {
    case plain, bubble
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plain: "Full width"
        case .bubble: "Bubbles"
        }
    }
}

/// Display choices for the chat page. Nothing here is stored, and there is no account.
@MainActor @Observable
public final class ChatChrome {
    public var userName = "friend"
    public var glass = true
    public var crabRoams = true
    public var modelLabel = "Demo"
    public var showThinking = true
    public var thinkingLook = "bubbles"
    /// `crab` lifts a short sign, `whisper` uses a bubble, `plain` leaves the text alone.
    public var voiceStyle = "crab"
    public var showMeter = false
    public var voiceRule = false
    public var glassReplies = true
    public var showCacheStats = false
    public var moodWallpaper = false
    public var bgBlur = 6.0
    public var bgDim = 0.3
    /// Local leaf toggle in the composer. It does not contact anything.
    public var notesOn = false

    var palette: Palette = .official {
        didSet { ThemeStore.shared.palette = palette }
    }
    var replyStyle: ReplyStyle = .plain

    var readingStyle: ReadingStyle {
        ReadingStyle(font: .system, scale: 1, lineGap: 4, fontReady: true)
    }

    public init() {
        ThemeStore.shared.palette = palette
    }

    func toolShow(_ kind: ToolCall.Kind) -> String { "collapsed" }
}
