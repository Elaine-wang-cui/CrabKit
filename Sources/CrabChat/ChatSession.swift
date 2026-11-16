import CrabKit
import Foundation
import Observation
import UIKit

/// In-memory chat. A send appends a row and plays a local sample (think, walk, hop).
/// The typed line is not used as the reply. Nothing is written to UserDefaults or an app group.
@MainActor
@Observable
public final class ChatSession {
    var conversation: Conversation?
    var isStreaming = false
    var turnBusy = false
    var crab: CrabState = .idle
    var cue: CrabCue?
    var conversations: [Conversation] = []

    private(set) var focusID: UUID?
    private(set) var focusSerial = 0
    private(set) var prefill = ""
    private(set) var prefillAttachments: [Attachment] = []
    private(set) var prefillSerial = 0

    var activeProject: ChatProject? { conversation?.project }

    private var task: Task<Void, Never>?
    private var job = UUID()
    private var cueSerial = 0

    /// Short local lines. They are not anyone's chat, and they are not sent anywhere.
    private static let replies = [
        "This reply is written on device. Nothing was sent anywhere.",
        "The crab thinks, then walks, then hops when the line is done.",
        "The transcript stays in memory until you leave this screen.",
        "You can branch a message, add a reaction, or scroll back up.",
    ]

    public init() {}

    func newChat(in project: ChatProject? = nil) {
        stop()
        conversation = nil
        focusID = nil
        crab = .idle
        MoodMeter.shared.reset()
        if let project {
            let convo = Conversation(title: "New chat")
            convo.project = project
            conversations.append(convo)
            conversation = convo
        }
    }

    func open(_ convo: Conversation, focus: UUID? = nil) {
        if convo.id != conversation?.id {
            stop()
            conversation = convo
            crab = .idle
            MoodMeter.shared.load(from: convo.sortedMessages)
        }
        focusID = focus
        if focus != nil { focusSerial += 1 }
    }

    @discardableResult
    func send(_ raw: String, attachments: [Attachment] = []) -> (userID: UUID, replyID: UUID)? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, !isStreaming, !turnBusy else { return nil }

        let convo: Conversation
        if let existing = conversation {
            convo = existing
        } else {
            let fallback = attachments.first.map { $0.kind == .image ? "Image" : $0.name } ?? "New chat"
            convo = Conversation(title: text.isEmpty ? fallback : String(text.prefix(24)))
            conversations.append(convo)
            conversation = convo
        }

        let user = ChatMessage(role: .user, text: text)
        user.attachments = attachments
        convo.messages.append(user)
        convo.updatedAt = .now
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let reply = beginReply(in: convo, reusing: nil)
        return (user.id, reply.id)
    }

    func regenerate() {
        guard !isStreaming, !turnBusy, let convo = conversation,
              let last = convo.sortedMessages.last, last.role == .assistant else { return }
        Speaker.shared.stop()
        last.startNewVersion()
        _ = beginReply(in: convo, reusing: last)
    }

    func showVersion(_ message: ChatMessage, _ index: Int) {
        guard !isStreaming || message.id != conversation?.sortedMessages.last?.id else { return }
        message.showVersion(index)
        UISelectionFeedbackGenerator().selectionChanged()
        if conversation?.sortedMessages.last?.id == message.id {
            MoodMeter.shared.load(from: conversation?.sortedMessages ?? [])
        }
    }

    func fork(at message: ChatMessage) {
        guard !isStreaming, !turnBusy, let source = conversation else { return }
        let all = source.sortedMessages
        guard let index = all.firstIndex(where: { $0.id == message.id }) else { return }
        let keep = message.role == .assistant ? Array(all[...index]) : Array(all[..<index])
        let siblings = conversations.filter { $0.parentID == source.id }.count
        let base = source.title.components(separatedBy: " · branch").first ?? source.title
        let branch = Conversation(title: "\(base) · branch \(siblings + 1)")
        branch.parentID = source.id
        branch.forkNote = String(message.text.replacingOccurrences(of: "\n", with: " ").prefix(28))
        branch.project = source.project
        branch.messages = keep.map { $0.duplicate() }
        branch.updatedAt = .now
        conversations.append(branch)
        open(branch)
        if message.role == .user {
            prefill = message.text
            prefillAttachments = message.attachments
            prefillSerial += 1
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func react(_ message: ChatMessage, with emoji: String) {
        message.reaction = emoji
        message.saveVersion()
        if !emoji.isEmpty {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            fire(.reaction(emoji))
        }
    }

    func showSign(_ text: String) {
        fire(.sign(text))
    }

    func stop() {
        job = UUID()
        task?.cancel()
        task = nil
        isStreaming = false
        turnBusy = false
        if crab != .happy { crab = .idle }
        IslandCrab.shared.cancel()
    }

    private func fire(_ kind: CrabCue.Kind) {
        cueSerial += 1
        cue = CrabCue(kind: kind, serial: cueSerial)
    }

    @discardableResult
    private func beginReply(in convo: Conversation, reusing: ChatMessage?) -> ChatMessage {
        let reply: ChatMessage
        if let reusing {
            reply = reusing
        } else {
            reply = ChatMessage(role: .assistant, text: "")
            reply.createdAt = Date().addingTimeInterval(0.001)
            convo.messages.append(reply)
        }
        task?.cancel()
        let job = UUID()
        self.job = job
        turnBusy = true
        let sample = Self.replies.randomElement() ?? Self.replies[0]
        task = Task { [weak self] in
            guard let self else { return }
            await Task.yield()
            guard self.job == job, !Task.isCancelled else { return }
            self.isStreaming = true
            self.crab = .thinking
            reply.thinking = "Drafting a reply."
            IslandCrab.shared.start(title: "Demo", style: .heart)
            try? await Task.sleep(for: .milliseconds(700))
            guard self.job == job, !Task.isCancelled else {
                self.abandon(job, reply: reply)
                return
            }
            self.crab = .walking
            reply.thinkingSeconds = 0.7
            IslandCrab.shared.set(.writing)
            for character in sample {
                guard self.job == job, !Task.isCancelled else {
                    self.abandon(job, reply: reply)
                    return
                }
                reply.text.append(character)
                convo.updatedAt = .now
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard self.job == job, !Task.isCancelled else {
                self.abandon(job, reply: reply)
                return
            }
            self.crab = .happy
            IslandCrab.shared.finish()
            try? await Task.sleep(for: .milliseconds(450))
            guard self.job == job else { return }
            self.crab = .idle
            self.isStreaming = false
            self.turnBusy = false
            self.task = nil
        }
        return reply
    }

    private func abandon(_ job: UUID, reply: ChatMessage) {
        guard self.job == job else { return }
        if reply.notice.isEmpty, reply.text.isEmpty { reply.notice = "Stopped." }
        isStreaming = false
        turnBusy = false
        task = nil
        crab = .idle
        IslandCrab.shared.cancel()
    }
}
