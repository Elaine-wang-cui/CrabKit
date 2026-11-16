import Foundation

/// Stand-in for read-aloud. This package does not play or upload audio.
@MainActor @Observable
final class Speaker {
    static let shared = Speaker()

    var failedID: UUID?
    var errorText = ""
    var loadingID: UUID?
    var playingID: UUID?

    func isBusy(_ id: UUID) -> Bool { false }

    func toggle(_ message: ChatMessage, settings: ChatChrome) {
        if settings.voiceStyle == "plain" || message.text.isEmpty { return }
    }

    func stop() {}
}
