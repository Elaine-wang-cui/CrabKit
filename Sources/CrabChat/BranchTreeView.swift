import SwiftUI

/// 分叉树：当前这段对话所在的整棵树，一层层缩进画出来，点哪根枝就去哪段
struct BranchTreeView: View {
    let session: ChatSession
    @Environment(\.dismiss) private var dismiss

    private var all: [Conversation] { session.conversations }

    private struct Node: Identifiable {
        let convo: Conversation
        let depth: Int
        /// 每一层前面要不要画竖线（上面的枝还有没画完的兄弟）
        let rails: [Bool]
        let isLast: Bool
        var id: UUID { convo.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(nodes) { node in
                        row(node)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(Theme.background)
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: 树

    private var byID: [UUID: Conversation] {
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// 顺着爹往上找到根；爹被删了就停在这
    private var root: Conversation? {
        guard var c = session.conversation else { return nil }
        let map = byID
        var seen: Set<UUID> = [c.id]
        while let p = c.parentID, let up = map[p], !seen.contains(up.id) {
            seen.insert(up.id)
            c = up
        }
        return c
    }

    private var nodes: [Node] {
        guard let root else { return [] }
        let kids = Dictionary(grouping: all.filter { $0.parentID != nil }, by: { $0.parentID! })
        var out: [Node] = []
        var seen: Set<UUID> = []
        func walk(_ c: Conversation, depth: Int, rails: [Bool], last: Bool) {
            guard seen.insert(c.id).inserted else { return }
            out.append(Node(convo: c, depth: depth, rails: rails, isLast: last))
            let children = (kids[c.id] ?? []).sorted { $0.createdAt < $1.createdAt }
            for (i, child) in children.enumerated() {
                walk(child, depth: depth + 1, rails: rails + [!last && depth > 0], last: i == children.count - 1)
            }
        }
        walk(root, depth: 0, rails: [], last: true)
        return out
    }

    private func row(_ node: Node) -> some View {
        let current = node.convo.id == session.conversation?.id
        let count = node.convo.messages.count
        return Button {
            session.open(node.convo)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 0) {
                // 前面几层的竖线
                ForEach(Array(node.rails.dropFirst().enumerated()), id: \.offset) { _, on in
                    Rectangle()
                        .fill(on ? Theme.border : .clear)
                        .frame(width: 1.2)
                        .frame(width: 22)
                }
                if node.depth > 0 {
                    // 这一层的拐角
                    Path { p in
                        p.move(to: CGPoint(x: 11, y: 0))
                        p.addLine(to: CGPoint(x: 11, y: 22))
                        p.addQuadCurve(to: CGPoint(x: 22, y: 30), control: CGPoint(x: 11, y: 30))
                        if !node.isLast {
                            p.move(to: CGPoint(x: 11, y: 22))
                            p.addLine(to: CGPoint(x: 11, y: 64))
                        }
                    }
                    .stroke(Theme.border, lineWidth: 1.2)
                    .frame(width: 22, height: 64, alignment: .topLeading)
                }
                HStack(spacing: 10) {
                    Circle()
                        .fill(current ? Theme.accent : Theme.textSecondary.opacity(0.35))
                        .frame(width: current ? 11 : 8, height: current ? 11 : 8)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.convo.title)
                            .font(.subheadline.weight(current ? .semibold : .regular))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Group {
                            if node.depth == 0 {
                                Text("Main · \(count) messages")
                            } else if node.convo.forkNote.isEmpty {
                                Text("\(count) messages")
                            } else {
                                Text("From “\(node.convo.forkNote)” · \(count) messages")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if current {
                        Text("Here")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(current ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(minHeight: 64, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
