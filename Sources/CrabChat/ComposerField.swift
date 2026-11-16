import SwiftUI
import UIKit

/// The composer's text box. A UITextView instead of SwiftUI's TextField, because TextField
/// can't be cleared reliably while a Chinese or Japanese keyboard still holds composing
/// (marked) text: the binding goes empty but the box keeps showing the old words on top
/// of the placeholder. Here the composing text is committed and wiped together on send.
struct ComposerField: UIViewRepresentable {
    @Binding var text: String
    /// True while the box shows anything, composing text included; the placeholder hides on this
    @Binding var hasContent: Bool
    var minLines: Int = 2
    var maxLines: Int = 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.textColor = UIColor(Theme.textPrimary)
        tv.tintColor = UIColor(Theme.accent)
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.keyboardDismissMode = .interactive
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.text = text
        context.coordinator.synced = text
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        tv.textColor = UIColor(Theme.textPrimary)
        // Only an outside change (send clearing it, a starter chip, a fork prefill) touches the box.
        // Comparing with what we last synced, not tv.text, keeps composing text alive across redraws.
        guard text != context.coordinator.synced, !context.coordinator.editing else { return }
        context.coordinator.synced = text
        // Commit whatever the keyboard is still composing, then replace it all.
        // Without unmarkText the keyboard writes its composing text back after we clear.
        if tv.markedTextRange != nil { tv.unmarkText() }
        tv.text = text
        if text.isEmpty { tv.undoManager?.removeAllActions() }
        context.coordinator.report(tv)
        tv.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let line = tv.font?.lineHeight ?? 22
        let lo = ceil(line * CGFloat(minLines))
        let hi = ceil(line * CGFloat(maxLines))
        let fit = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let scroll = fit > hi
        if tv.isScrollEnabled != scroll {
            DispatchQueue.main.async { tv.isScrollEnabled = scroll }
        }
        return CGSize(width: width, height: min(max(fit, lo), hi))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerField
        /// Set while UIKit is handing us a change, so updateUIView doesn't fight it
        var editing = false
        /// The text the binding and the box last agreed on
        var synced = ""

        init(_ parent: ComposerField) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            editing = true
            // Composing text stays out of the binding until the keyboard commits it,
            // the same as TextField, so a half-typed pinyin never gets sent
            let committed = committedText(tv)
            synced = committed
            if parent.text != committed { parent.text = committed }
            report(tv)
            editing = false
            tv.invalidateIntrinsicContentSize()
        }

        func report(_ tv: UITextView) {
            let has = !tv.text.isEmpty
            if parent.hasContent != has {
                let binding = parent.$hasContent
                DispatchQueue.main.async { binding.wrappedValue = has }
            }
        }

        private func committedText(_ tv: UITextView) -> String {
            guard let marked = tv.markedTextRange else { return tv.text }
            let start = tv.offset(from: tv.beginningOfDocument, to: marked.start)
            let end = tv.offset(from: tv.beginningOfDocument, to: marked.end)
            let ns = tv.text as NSString
            guard start >= 0, end <= ns.length, start <= end else { return tv.text }
            return ns.replacingCharacters(in: NSRange(location: start, length: end - start), with: "")
        }
    }
}
