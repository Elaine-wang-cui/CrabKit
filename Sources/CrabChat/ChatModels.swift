import Foundation

/// A file or image the composer is holding. Kept in memory with the message.
struct Attachment: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case image, pdf, text }
    var id: UUID = UUID()
    var kind: Kind
    var name: String
    var mediaType: String
    var data: Data
}

enum Role: String, Codable {
    case user
    case assistant
}

/// A named group of chats. Instructions and files from the private app are not here.
@Observable
final class ChatProject: Identifiable {
    var id = UUID()
    var name: String

    init(name: String) {
        self.name = name
    }
}

/// One conversation held in memory.
@Observable
final class Conversation: Identifiable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []
    /// Optional caption shown above the transcript.
    var notesTitle = ""
    var notesBody = ""
    var parentID: UUID?
    var forkNote = ""
    var project: ChatProject?

    init(title: String = "New chat") {
        self.title = title
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}

/// One visible version of a reply.
struct ReplyVersion: Equatable {
    var text = ""
    var thinking = ""
    var thinkingSeconds: Double = 0
    var toolNotes: [String] = []
    var toolCalls: [ToolCall] = []
    var notice = ""
    var isError = false
    var reaction = ""
}

/// A tool card inside a reply. Nothing here calls a server.
struct ToolCall: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case memory, notes, connector }
    var id: String
    var name: String
    var label: String
    var kind: Kind
    var offset: Int
    var input: String = ""
    var result: String = ""
    var isError = false
    var done = false

    var summary: String {
        guard let data = input.data(using: .utf8),
              let obj = try? JSONDecoder().decode(JSONValue.self, from: data).objectValue, !obj.isEmpty else { return "" }
        let preferred = ["content", "text", "query", "title", "name"]
        for key in preferred {
            if let s = obj[key]?.stringValue, !s.isEmpty { return s }
        }
        for (_, value) in obj.sorted(by: { $0.key < $1.key }) {
            if let s = value.stringValue, !s.isEmpty { return s }
        }
        return ""
    }
}

/// A transcript row. Reference type so a streaming reply can grow in place.
@Observable
final class ChatMessage: Identifiable {
    var id = UUID()
    var role: Role
    var text = ""
    var thinking = ""
    var thinkingSeconds: Double = 0
    var toolNotes: [String] = []
    var toolCalls: [ToolCall] = []
    var notice = ""
    var isError = false
    var reaction = ""
    /// Optional note under a user bubble. The demo leaves this empty.
    var recalled = ""
    var cacheRead = 0
    var cacheWrite = 0
    var freshInput = 0
    var versions: [ReplyVersion] = []
    var versionIndex = 0
    var attachments: [Attachment] = []
    var createdAt = Date()

    init(role: Role, text: String) {
        self.role = role
        self.text = text
        self.createdAt = .now
    }

    var roleRaw: String {
        get { role.rawValue }
        set { role = Role(rawValue: newValue) ?? .user }
    }

    var versionCount: Int { max(1, versions.isEmpty ? 1 : versions.count) }

    func duplicate() -> ChatMessage {
        let copy = ChatMessage(role: role, text: text)
        copy.thinking = thinking
        copy.thinkingSeconds = thinkingSeconds
        copy.toolNotes = toolNotes
        copy.toolCalls = toolCalls
        copy.notice = notice
        copy.isError = isError
        copy.reaction = reaction
        copy.recalled = recalled
        copy.versions = versions
        copy.versionIndex = versionIndex
        copy.attachments = attachments
        copy.createdAt = createdAt
        return copy
    }

    private var snapshot: ReplyVersion {
        ReplyVersion(text: text, thinking: thinking, thinkingSeconds: thinkingSeconds, toolNotes: toolNotes,
                     toolCalls: toolCalls, notice: notice, isError: isError, reaction: reaction)
    }

    private func apply(_ version: ReplyVersion) {
        text = version.text
        thinking = version.thinking
        thinkingSeconds = version.thinkingSeconds
        toolNotes = version.toolNotes
        toolCalls = version.toolCalls
        notice = version.notice
        isError = version.isError
        reaction = version.reaction
    }

    func saveVersion() {
        guard !versions.isEmpty else { return }
        let index = min(max(0, versionIndex), versions.count - 1)
        versions[index] = snapshot
    }

    func startNewVersion() {
        var list = versions
        if list.isEmpty {
            list = [snapshot]
        } else {
            list[min(max(0, versionIndex), list.count - 1)] = snapshot
        }
        apply(ReplyVersion())
        list.append(snapshot)
        versionIndex = list.count - 1
        versions = list
    }

    func showVersion(_ index: Int) {
        guard versions.count > 1, versions.indices.contains(index), index != versionIndex else { return }
        versions[min(max(0, versionIndex), versions.count - 1)] = snapshot
        versionIndex = index
        apply(versions[index])
    }
}
