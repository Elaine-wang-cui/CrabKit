import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ComposerView: View {
    @Binding var text: String
    /// 还没发出去的图片和文件
    @Binding var attachments: [Attachment]
    var isStreaming: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    /// 语音按钮。这个包里只打开一张说明，不连麦克风。
    var onCall: (() -> Void)? = nil
    @Environment(ChatChrome.self) private var settings
    /// The box shows something (composing text counts), so the placeholder stays hidden
    @State private var hasContent = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var rejected = false

    private static let maxAttachments = 10

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 10) {
            if !attachments.isEmpty {
                pendingRow
            }
            // Streaming, the crab, and a flight redraw this view. None of those may
            // push the binding back into the box: that is how a cleared word reappears
            // and the next word sticks to it. Only a real text change updates the box.
            ComposerBox(text: $text, hasContent: $hasContent)
                .equatable()
                .background {
                    ComposerFrameReader()
                    ComposerAnchorView()
                }
                .padding(.horizontal, 4)
                .overlay(alignment: .topLeading) {
                    if !hasContent && text.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Message")
                        }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 4)
                        .allowsHitTesting(false)
                    }
                }

            toolRow
        }
        .padding(12)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), tint: Theme.userBubble, on: settings.glass, strength: 0.55)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.accent.opacity(0.85), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
        .padding(.horizontal, 12)

        // 输入框下面那行灰色小字
        Text(rejected ? "A file couldn't be read. Images, PDFs and text files work." : "Replies here are local and stay on this screen.")
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems,
                      maxSelectionCount: max(1, Self.maxAttachments - attachments.count), matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let a = AttachmentLoader.image(data: data) else { continue }
                    add(a)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let a = AttachmentLoader.image(image, name: "Photos") { add(a) }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            var bad = false
            for url in urls {
                if let a = AttachmentLoader.file(at: url) { add(a) } else { bad = true }
            }
            if bad { flagRejected() }
        }
    }

    private func add(_ a: Attachment) {
        guard attachments.count < Self.maxAttachments else { return }
        withAnimation(.snappy) { attachments.append(a) }
    }

    /// Snapshot first (`onSend` reads the binding), then empty the box before this
    /// action returns. A key event cannot run until then, so it cannot be wiped by a
    /// later clear and it cannot be appended to the word that was just sent.
    /// Composing text is committed and then the whole box is wiped, so committed
    /// characters do not stay behind. A refused send leaves the draft alone.
    private func sendAndClear() {
        SendMark.event("send.button")
        let before = text
        // Prefer the box that actually holds this draft. A tap can move first
        // responder, and telling the keyboard about the edit makes it insert the
        // word again, which is how the next word gets glued on.
        let tv = composerBox(matching: before)
        onSend()
        // A refused send (still streaming) leaves the draft. Don't touch the box.
        guard text.isEmpty, let tv, tv.window != nil else { return }
        wipe(tv)
    }

    private func composerBox(matching draft: String) -> UITextView? {
        let candidates = [UIResponder.chatFirst as? UITextView, ComposerAnchor.box].compactMap { $0 }
        return candidates.first { holds(draft, $0) }
    }

    private func holds(_ draft: String, _ tv: UITextView) -> Bool {
        if tv.markedTextRange != nil, !draft.isEmpty { return true }
        let shown = tv.text ?? ""
        if shown == draft { return true }
        return !draft.isEmpty && shown.hasPrefix(draft)
    }

    /// Same clear as the field's own update: commit composing text, then wipe.
    /// Notifying the keyboard here is what puts the old word back.
    private func wipe(_ tv: UITextView) {
        if tv.markedTextRange != nil { tv.unmarkText() }
        tv.text = ""
        tv.undoManager?.removeAllActions()
        tv.delegate?.textViewDidChange?(tv)
        if !text.isEmpty { text = "" }
        hasContent = false
        SendMark.event("composer.cleared")
    }

    private func flagRejected() {
        rejected = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            rejected = false
        }
    }

    private var toolRow: some View {
        HStack(spacing: 10) {
            attachMenu
            notesButton
            Spacer()
            Text(settings.modelLabel)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            callButton
            sendButton
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
    }

    private var attachMenu: some View {
        Menu {
            Button { showPhotos = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
            }
            Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
        } label: {
            Image(systemName: "plus")
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(Theme.border))
        }
        .disabled(attachments.count >= Self.maxAttachments)
        .accessibilityLabel("Add photos or files")
    }

    private var notesButton: some View {
        Button {
            settings.notesOn.toggle()
        } label: {
            Image(systemName: "leaf")
                .frame(width: 32, height: 32)
                .foregroundStyle(settings.notesOn ? Theme.accent : Theme.textSecondary)
                .background(settings.notesOn ? Theme.accent.opacity(0.12) : .clear, in: Circle())
                .overlay(Circle().stroke(settings.notesOn ? Theme.accent.opacity(0.4) : Theme.border))
        }
        .accessibilityLabel("Notes")
    }

    @ViewBuilder
    private var callButton: some View {
        if let onCall {
            Button(action: onCall) {
                Image(systemName: "phone")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(Theme.border))
            }
            .accessibilityLabel("Call")
        }
    }

    private var sendButton: some View {
        let lit = isStreaming || canSend
        return Button(action: isStreaming ? onStop : sendAndClear) {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(lit ? Color.white : Theme.textSecondary.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(lit ? Theme.accent : Theme.border.opacity(0.7), in: Circle())
                .shadow(color: Theme.accent.opacity(lit ? 0.45 : 0), radius: lit ? 8 : 0)
                .scaleEffect(lit ? 1 : 0.9)
                .animation(.spring(duration: 0.35, bounce: 0.45), value: lit)
        }
        .disabled(!isStreaming && !canSend)
    }

    /// 输入框上面一排待发的缩略图，右上角小叉可以去掉
    private var pendingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { a in
                    AttachmentThumb(attachment: a, size: 60)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.snappy) { attachments.removeAll { $0.id == a.id } }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Color.black.opacity(0.6), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("Remove")
                        }
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
    }
}

/// The text box, isolated from every composer redraw that is not a text change.
private struct ComposerBox: View, Equatable {
    @Binding var text: String
    @Binding var hasContent: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        ComposerField(text: $text, hasContent: $hasContent)
    }
}

/// Remembers the composer's text view from the view next to it, not from whoever
/// is first responder when Send is tapped.
private struct ComposerAnchorView: UIViewRepresentable {
    func makeUIView(context: Context) -> ComposerAnchor { ComposerAnchor() }
    func updateUIView(_ uiView: ComposerAnchor, context: Context) { uiView.remember() }
}

private final class ComposerAnchor: UIView {
    static weak var box: UITextView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        remember()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if Self.box == nil { remember() }
    }

    func remember() {
        if let box = Self.box, box.window != nil { return }
        var node: UIView? = self
        for _ in 0..<4 {
            guard let current = node else { return }
            var budget = 40
            if let tv = Self.find(current, depth: 6, budget: &budget) {
                Self.box = tv
                return
            }
            node = current.superview
        }
    }

    private static func find(_ view: UIView, depth: Int, budget: inout Int) -> UITextView? {
        if depth < 0 || budget <= 0 { return nil }
        budget -= 1
        if let tv = view as? UITextView { return tv }
        for sub in view.subviews {
            if let tv = find(sub, depth: depth - 1, budget: &budget) { return tv }
        }
        return nil
    }
}

private enum ChatFirstResponder {
    static weak var found: UIResponder?
}

extension UIResponder {
    @objc func chatNoteFirstResponder() {
        ChatFirstResponder.found = self
    }

    static var chatFirst: UIResponder? {
        ChatFirstResponder.found = nil
        UIApplication.shared.sendAction(#selector(chatNoteFirstResponder), to: nil, from: nil, for: nil)
        return ChatFirstResponder.found
    }
}
