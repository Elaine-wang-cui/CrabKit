import CrabKit
import SwiftUI

/// One presented frame, or `cap` seconds, whichever comes first.
private final class InsertSignal: NSObject {
    private var link: CADisplayLink?
    private var fired = false
    private var keep: InsertSignal?
    private let done: () -> Void

    private init(_ done: @escaping () -> Void) { self.done = done }

    static func wait(cap: TimeInterval) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let gate = InsertSignal { cont.resume() }
            gate.arm(cap: cap)
        }
    }

    private func arm(cap: TimeInterval) {
        keep = self
        let link = CADisplayLink(target: self, selector: #selector(frame))
        link.add(to: .main, forMode: .common)
        self.link = link
        DispatchQueue.main.asyncAfter(deadline: .now() + cap) { [weak self] in
            self?.fire()
        }
    }

    @objc private func frame() { fire() }

    private func fire() {
        guard !fired else { return }
        fired = true
        link?.invalidate()
        link = nil
        let done = self.done
        keep = nil
        done()
    }
}

public struct ChatView: View {
    @Bindable public var session: ChatSession
    public var onMenu: () -> Void
    public var onSettings: () -> Void

    public init(session: ChatSession, onMenu: @escaping () -> Void = {}, onSettings: @escaping () -> Void = {}) {
        self.session = session
        self.onMenu = onMenu
        self.onSettings = onSettings
    }
    @Environment(ChatChrome.self) private var settings
    @State private var draft = ""
    @State private var pending: [Attachment] = []
    /// 通话页开着
    @State private var calling = false
    /// 分叉树开着
    @State private var showTree = false
    /// Flight state lives on a class so a moving copy never invalidates this view, and never the field.
    @State private var pop = SendFlightModel()
    /// 这段对话有上一层或者下一层，顶上才放分叉树按钮
    private var inTree: Bool {
        guard let c = session.conversation else { return false }
        return c.parentID != nil || session.conversations.contains { $0.parentID == c.id }
    }

    /// Whether this chat has any row. Does not sort. Sorting here ran on every Send, before the box was wiped.
    private var hasMessages: Bool { session.conversation?.messages.isEmpty == false }

    public var body: some View {
        laidOut()
            .background { Color.clear.accessibilityAction(named: "Options") { onSettings() } }
    }

    private func laidOut() -> some View {
        let started = CFAbsoluteTimeGetCurrent()
        defer { SendMark.body("ChatView", seconds: CFAbsoluteTimeGetCurrent() - started) }
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                if !hasMessages {
                    EmptyStateView(
                        name: settings.userName,
                        typing: draft.count,
                        cue: session.cue,
                        projectName: session.activeProject?.name,
                        onStarter: { draft = $0 }
                    )
                } else {
                    TranscriptPane(session: session, pop: pop)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // 对话区的范围报给小螃蟹：拎着它能放到这块里任何地方
                GeometryReader { g in
                    Color.clear
                        .onAppear { CrabStage.shared.area = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, f in CrabStage.shared.area = f }
                }
            }
        }
        // 顶栏浮在对话上面，往上滑的字从毛玻璃后面糊糊地透过去
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar.background(GlassBarBackground(on: settings.glass))
        }
        .background {
            ChatBackdrop().ignoresSafeArea()
        }
        .environment(\.reading, settings.readingStyle)
        .onAppear { FontLoader.shared.ensure(settings.readingStyle.font) }
        .sheet(isPresented: $showTree) {
            BranchTreeView(session: session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: session.prefillSerial) { _, _ in
            draft = session.prefill
            pending = session.prefillAttachments
        }
        .fullScreenCover(isPresented: $calling) {
            VoiceCallNotice()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                // 趴在输入框上沿的那只
                if hasMessages {
                    RoamingCrab(working: session.crab, roams: settings.crabRoams, typing: draft.count, cue: session.cue)
                        .padding(.bottom, -6)
                }
                SteadyComposer(
                    text: $draft,
                    attachments: $pending,
                    isStreaming: session.isStreaming,
                    onSend: send,
                    onStop: { session.stop() },
                    onCall: { calling = true }
                )
                .equatable()
            }
        }
        .overlay { SendFlightLayer(pop: pop) }
        .coordinateSpace(name: SendFlightSpace.name)
        .onPreferenceChange(ComposerTextFrameKey.self, perform: noteComposer)
        .onPreferenceChange(ComposerWindowFrameKey.self, perform: noteComposerWindow)
        .onPreferenceChange(SendFlightDestKey.self, perform: noteDest)
        .onPreferenceChange(FlightWindowDestKey.self, perform: noteWindowDest)
        .onPreferenceChange(ColumnWidthKey.self, perform: noteColumn)
    }

    private var topBar: some View {
        // 标题单独放正中间，两边按钮多一个少一个都不会把它挤歪
        HStack {
            CircleButton(systemName: "line.3.horizontal", action: onMenu)
            Spacer()
            if inTree {
                CircleButton(systemName: "arrow.triangle.branch") { showTree = true }
                    .accessibilityLabel("Branches")
            }
            CircleButton(systemName: "square.and.pencil") {
                pop.finish()
                session.newChat()
                draft = ""
                pending = []
            }
        }
        .overlay {
            VStack(spacing: 1) {
                Text(session.conversation?.title ?? "New chat")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                Text(session.activeProject.map { "\($0.name) · \(settings.modelLabel)" } ?? settings.modelLabel)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: 190)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func send() {
        SendMark.event("send.tap")
        // While a reply is streaming the button is Stop. Return before clearing
        // so a tap that still reaches here keeps the draft. turnBusy covers the
        // moment before isStreaming flips, which is the same refusal.
        guard !session.isStreaming, !session.turnBusy else { return }
        let text = draft
        let files = pending
        let origin = pop.composerFrame
        let bottom = pop.atBottom
        SendMark.event("send.draft")
        draft = ""
        pending = []
        // Snapshot only. The copy starts its diagonal now; it does not write the field.
        // Window layer only when there is no transcript yet. Every later send uses the
        // in-chat copy, which already tracked a scrolling row.
        // `messages` is already faulted while the list is on screen. The mark is here
        // so a cold fault shows up as a gap before send.welcome, not as a silent stall.
        SendMark.event("send.beforeEmpty")
        let welcome = session.conversation?.messages.isEmpty ?? true
        SendMark.event("send.welcome \(welcome)")
        let ticket = pop.claim(text: text, files: files, origin: origin, wasAtBottom: bottom, windowFlight: welcome)
        SendMark.event("send.claimed")
        if welcome, let ticket {
            FlightHost.shared.onLanded = { gen in pop.land(generation: gen) }
            FlightHost.shared.onReleased = { gen in pop.releaseWindow(generation: gen) }
            FlightHost.shared.scrollSettled = { !pop.scrollActive }
            FlightHost.shared.begin(
                text: ticket.text,
                field: pop.composerWindow,
                transcript: CrabStage.shared.area,
                generation: pop.generation
            )
        }
        // The coast animation is added in the SwiftUI update that follows this return.
        // Flush it on the next presented frame (or at 80ms), then insert. A kill at
        // 0.16s still finds the journal. session.send itself is the persist.
        SendFlightTiming.deferFirstInsert = false
        SendMark.event("send.defer")
        Task { @MainActor in
            let generation = self.pop.generation
            // An early return (cancel, or the wait throwing) still has to release
            // this send. Otherwise its coast and list wait forever.
            defer { SendFlightModel.noteInserted(generation) }
            await InsertSignal.wait(cap: 0.08)
            if Task.isCancelled { return }
            CATransaction.flush()
            SendMark.Signpost.caCommit()
            SendMark.event("send.beforeInsert coast=\(SendFlightModel.coastFlushed)")
            self.commitSend(text, files: files, ticket: ticket)
        }
    }

    /// Insert the snapshot. Does not read or write the composer.
    private func commitSend(_ text: String, files: [Attachment], ticket: SendTicket?) {
        SendMark.event("commit.begin")
        let started = CFAbsoluteTimeGetCurrent()
        var placed = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        SendMark.Signpost.beginCommit()
        withTransaction(transaction) {
            // Ids of the rows this call created. The relationship array is unordered.
            SendMark.event("commit.beforeSend")
            let sent = session.send(text, attachments: files)
            SendMark.event("commit.afterSend")
            guard let ticket, let sent, pop.ticketID == ticket.id else { return }
            pop.attach(userID: sent.userID)
            placed = true
        }
        SendMark.Signpost.endCommit()
        SendMark.Signpost.beginAfterInsert()
        if let ticket, !placed, pop.ticketID == ticket.id {
            // The send was refused after the box had already cleared (streaming started
            // in the gap). Drop this copy only. Don't put the text back.
            pop.finish()
        }
        if ticket == nil {
            DispatchQueue.main.async { self.pop.requestScroll(fast: false) }
        }
        SendMark.event(String(format: "commit.done %.1fms", (CFAbsoluteTimeGetCurrent() - started) * 1000))
    }

    private func noteComposer(_ frame: CGRect) {
        guard frame.isSendFrame, frame.changed(from: pop.composerFrame) else { return }
        pop.composerFrame = frame
    }

    private func noteComposerWindow(_ frame: CGRect) {
        guard frame.isSendFrame, frame.changed(from: pop.composerWindow) else { return }
        pop.composerWindow = frame
    }

    private func noteWindowDest(_ frame: CGRect) {
        guard pop.usesWindow, frame.isSendFrame else { return }
        FlightHost.shared.noteRow(frame)
    }

    private func noteDest(_ frame: CGRect) {
        pop.noteDestination(frame)
    }

    private func noteColumn(_ width: CGFloat) {
        guard width > 1, abs(width - pop.columnWidth) > 0.5 else { return }
        pop.columnWidth = width
    }
}

/// Holds the last sort so a body refresh during the insert does not sort again.
private final class RowCache {
    var rows: [ChatMessage] = []
    var key = ""

    func rows(in convo: Conversation?) -> [ChatMessage] {
        guard let convo else {
            rows = []
            key = ""
            return []
        }
        let count = convo.messages.count
        let tail = convo.messages.last
        let next = "\(count)|\(tail?.id.uuidString ?? "")|\(convo.updatedAt.timeIntervalSinceReferenceDate)"
        if next == key, rows.count == count { return rows }
        // A send appends one or two rows. Keep the prefix and sort only the new ones,
        // instead of sorting the whole history on the insert.
        if count > rows.count, count - rows.count <= 2, let last = rows.last {
            let known = Set(rows.map(\.id))
            let added = convo.messages.filter { !known.contains($0.id) }
            // Journal restore inserts older timestamps. Those have to be sorted into place.
            if added.count == count - rows.count, added.allSatisfy({ $0.createdAt >= last.createdAt }) {
                rows.append(contentsOf: added.sorted { $0.createdAt < $1.createdAt })
                key = next
                return rows
            }
        }
        rows = convo.messages.sorted { $0.createdAt < $1.createdAt }
        key = next
        return rows
    }
}

/// Skips the row body when the message, the last-row flag, and the conceal flag are unchanged.
/// An insert then rebuilds the new row and the previous last row, not the whole page.
private struct CachedRow<Content: View>: View, Equatable {
    let id: UUID
    let stamp: String
    let content: Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.stamp == rhs.stamp
    }

    var body: some View { content }
}

/// The stack inside the transcript scroll. Split out so the list type-checks on its own.
private struct TranscriptColumn: View {
    var session: ChatSession
    var pop: SendFlightModel
    var rows: [ChatMessage]
    var lastID: UUID?
    var probedTail: UUID?
    var probing: Bool
    var highlight: UUID?
    var timeReveal: CGFloat

    var body: some View {
        LazyVStack(alignment: .leading, spacing: RowContentSpace.spacing) {
            notesHeader
            messageList
            bottomCap
        }
    }

    @ViewBuilder
    private var notesHeader: some View {
        if let convo = session.conversation, !convo.notesTitle.isEmpty {
            NotesMark(title: convo.notesTitle, bodyText: convo.notesBody)
        }
    }

    private var messageList: some View {
        ForEach(rows) { message in
            TranscriptSlot(
                message: message,
                session: session,
                pop: pop,
                isLast: message.id == lastID,
                probe: probing && (pop.probeAll || message.id == probedTail),
                highlighted: highlight == message.id,
                timeReveal: timeReveal
            )
        }
    }

    private var bottomCap: some View {
        Color.clear
            .frame(height: 1)
            .id("bottom")
            .onAppear {
                pop.atBottom = true
                SendFlightModel.noteBottom()
            }
            .onDisappear { pop.atBottom = false }
    }
}

/// One transcript row, including the hidden placeholder used while a send is in flight.
private struct TranscriptSlot: View {
    var message: ChatMessage
    var session: ChatSession
    var pop: SendFlightModel
    var isLast: Bool
    var probe: Bool
    var highlighted: Bool
    var timeReveal: CGFloat

    var body: some View {
        if holdReply {
            Color.clear.frame(height: 0).id(message.id)
        } else {
            placedRow
        }
    }

    private var holdReply: Bool {
        pop.ticketID != nil && !pop.revealing
            && message.role == .assistant && isLast && message.text.isEmpty
    }

    private var hidden: Bool { pop.showsCopy(of: message.id) }

    private var placedRow: some View {
        CachedRow(id: message.id, stamp: stamp, content: row)
            .background {
                if probe {
                    RowContentProbe(id: message.id)
                }
            }
    }

    /// The crab only paints on the live last row. Leaving it off the other stamps
    /// keeps a crab tick from rebuilding the history.
    private var stamp: String {
        let live = isLast && session.isStreaming
        let crabStamp = isLast ? String(describing: session.crab) : ""
        return "\(message.text.hashValue)|\(message.roleRaw)|\(hidden)|\(isLast)|\(live)|\(crabStamp)|\(pop.usesWindow)|\(highlighted)|\(timeReveal)"
    }

    private var regenerate: (() -> Void)? {
        guard isLast, message.role == .assistant else { return nil }
        return { session.regenerate() }
    }

    private var react: ((String) -> Void)? {
        guard message.role == .assistant else { return nil }
        return { emoji in session.react(message, with: emoji) }
    }

    private var showVersion: ((Int) -> Void)? {
        guard message.role == .assistant else { return nil }
        return { index in session.showVersion(message, index) }
    }

    private var row: some View {
        MessageRow(
            message: message,
            session: session,
            isLive: isLast && session.isStreaming,
            crab: session.crab,
            onRegenerate: regenerate,
            onReact: react,
            onVoice: { line in session.showSign(line) },
            onVersion: showVersion,
            timeReveal: timeReveal
        )
        .id(message.id)
        .background { SearchHighlight(active: highlighted) }
        .opacity(hidden ? 0 : 1)
        // Full alpha in the handoff frame. A 0.16s fade starts late, after the copy
        // has already gone, and the landed bubble dims.
        .animation(nil, value: hidden)
        .accessibilityHidden(hidden)
        .transition(pop.usesWindow ? .identity : .opacity)
        .onAppear {
            SendFlightTrace.log("row appear id=\(message.id) role=\(message.role) hidden=\(hidden)")
            if !hidden, pop.usesWindow { FlightHost.shared.noteRowOpaque() }
        }
        .onChange(of: hidden) { _, now in
            if !now {
                SendFlightTrace.log("row opacity 1 id=\(message.id)")
                if pop.usesWindow { FlightHost.shared.noteRowOpaque() }
            }
        }
    }
}

/// The list. Owns scroll and the conceal flag, so neither one rebuilds the composer.
private struct TranscriptPane: View {
    @Bindable var session: ChatSession
    var pop: SendFlightModel
    /// 搜索跳过来的那条，亮一下
    @State private var highlight: UUID?
    /// 整页往左划了多远，划出每条右边的时间
    @State private var timeReveal: CGFloat = 0
    var body: some View { laidOut() }

    /// Sorted rows for this body. Reused until the count or the newest text changes,
    /// so an insert does not sort the same array again on every nested update.
    @State private var rowCache = RowCache()

    /// One sort for the whole list. Each row used to sort again to find the last id.
    private func laidOut() -> some View {
        let started = CFAbsoluteTimeGetCurrent()
        SendMark.Signpost.beginPane()
        defer {
            SendMark.Signpost.endPane()
            SendMark.body("TranscriptPane", seconds: CFAbsoluteTimeGetCurrent() - started)
        }
        let rows = rowCache.rows(in: session.conversation)
        let lastID = rows.last?.id
        let probing = pop.ticketID != nil
        // The empty assistant placeholder is last during a send and has no probe.
        // Tail credit has to name the last row that actually reports a frame.
        let probedTail: UUID? = {
            guard probing, !pop.revealing, let last = rows.last, last.role == .assistant, last.text.isEmpty else { return lastID }
            return rows.dropLast().last?.id ?? lastID
        }()
        let scrollCommand = pop.scrollCommand
        return ScrollViewReader { proxy in
            ScrollView {
                TranscriptColumn(
                    session: session,
                    pop: pop,
                    rows: rows,
                    lastID: lastID,
                    probedTail: probedTail,
                    probing: probing,
                    highlight: highlight,
                    timeReveal: timeReveal
                )
                .background { ColumnWidthReader() }
                .background {
                    GentleBottomScroll(
                        command: scrollCommand,
                        generation: SendFlightModel.currentGeneration,
                        fast: pop.scrollFast,
                        allowCatchUp: pop.allowCatchUp,
                        deadline: pop.started?.addingTimeInterval(SendFlightTiming.duration),
                        onIdle: { pop.scrollDidIdle() },
                        onCatchUp: { pop.beginCatchUp() }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // A send's row estimates must resolve in one frame. An inherited
                // animation turns that collapse into a quarter-second ease.
                .transaction { txn in
                    if pop.ticketID != nil { txn.disablesAnimations = true }
                }
                .coordinateSpace(name: RowContentSpace.name)
                .onPreferenceChange(RowContentFramesKey.self) { spots in
                    SendFlightModel.noteRowSpots(spots, lastID: probedTail)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(timeSwipe)
            .onChange(of: rows.last?.text.count) { _, _ in
                // Scrolled-up reading stays put. The glide owns the return to the bottom.
                // A send already owns the list. This nudge was a second writer.
                guard pop.atBottom, pop.ticketID == nil else { return }
                pop.requestScroll(fast: false)
            }
            .onChange(of: pop.ticketID) { _, id in
                // The reply row was held until the copy finished. One follow, then.
                guard id == nil, pop.atBottom else { return }
                pop.requestScroll(fast: false)
            }
            .onChange(of: session.conversation?.id) { _, _ in
                // Creating the conversation on send must not cancel the copy that send just armed.
                let kept = pop.flightUserID.map { id in
                    session.conversation?.messages.contains { $0.id == id } ?? false
                } ?? false
                if !kept {
                    pop.finish()
                    guard session.focusID == nil else { return }
                    pop.atBottom = true
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.focusSerial) { _, _ in
                jump(proxy)
            }
            .onAppear {
                if session.focusID != nil {
                    jump(proxy)
                } else if pop.ticketID == nil {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .overlay(alignment: .bottom) {
                Group {
                    if !pop.atBottom {
                        JumpToBottomButton {
                            withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        .padding(.bottom, 14)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.25), value: pop.atBottom)
            }
            .environment(\.sendFlightTarget, pop.flightUserID)
        }
    }

    /// 往左划，像短信那样把时间从右边拖出来，松手弹回去
    private var timeSwipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { v in
                guard !TimeReveal.busy, v.translation.width < 0,
                      abs(v.translation.width) > abs(v.translation.height) * 1.4 else { return }
                let pull = -v.translation.width
                // 拉过头了有点阻力
                let shown = pull < TimeReveal.full ? pull : TimeReveal.full + (pull - TimeReveal.full) * 0.15
                if timeReveal < TimeReveal.full, shown >= TimeReveal.full { Haptics.soft(0.35) }
                timeReveal = shown
            }
            .onEnded { _ in
                guard timeReveal > 0 else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0.2)) { timeReveal = 0 }
            }
    }

    /// 滚到搜到的那条，亮两秒
    private func jump(_ proxy: ScrollViewProxy) {
        guard let id = session.focusID else { return }
        Task { @MainActor in
            // 等新打开的对话先排好
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            withAnimation(.easeOut(duration: 0.25)) { highlight = id }
            try? await Task.sleep(for: .seconds(2.2))
            if highlight == id {
                withAnimation(.easeInOut(duration: 0.6)) { highlight = nil }
            }
        }
    }
}

/// Skips rebuilds while a flight or a streaming reply refreshes the page, so those
/// redraws can't push a stale binding back into the text view. Keystrokes still update it,
/// because the text value itself changed.
private struct SteadyComposer: View, Equatable {
    @Binding var text: String
    @Binding var attachments: [Attachment]
    var isStreaming: Bool
    var onSend: () -> Void
    var onStop: () -> Void
    var onCall: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.attachments == rhs.attachments && lhs.isStreaming == rhs.isStreaming
    }

    var body: some View {
        ComposerView(
            text: $text,
            attachments: $attachments,
            isStreaming: isStreaming,
            onSend: onSend,
            onStop: onStop,
            onCall: onCall
        )
    }
}

/// 搜索跳到的那条短暂垫一层淡色
private struct SearchHighlight: View {
    var active: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.accent.opacity(active ? 0.13 : 0))
            .padding(.horizontal, -10)
            .padding(.vertical, -8)
            .allowsHitTesting(false)
    }
}

/// 往上翻聊天时出现的圆钮，小螃蟹趴在上面打盹，点一下滑回最新
/// 对话最上面一行可选的备注，点开看正文
struct NotesMark: View {
    let title: String
    let bodyText: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label(title, systemImage: "leaf")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showing) {
            NavigationStack {
                ScrollView {
                    Text(bodyText)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct JumpToBottomButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .overlay(alignment: .top) {
                    CrabView(state: .sleepy, pixel: 1)
                        .offset(y: -15)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to latest")
    }
}

struct EmptyStateView: View {
    let name: String
    var typing: Int = 0
    var cue: CrabCue? = nil
    /// 在一组对话里开的新对话，问候下面标一下
    var projectName: String? = nil
    /// 点快捷开头，把这句放进输入框
    var onStarter: (String) -> Void = { _ in }

    /// 按时段换问候，同一天里不变
    private var greeting: String { TimeOfDay.now.greeting }

    private struct Starter: Hashable {
        let icon: String
        let text: String
    }

    private var starters: [Starter] {
        [
            Starter(icon: "bubble.left.and.bubble.right", text: "Say hello"),
            Starter(icon: "chevron.left.forwardslash.chevron.right", text: "Look at some code"),
            Starter(icon: "fork.knife", text: "What should I eat today"),
            Starter(icon: "pencil.line", text: "Help me write something"),
        ]
    }

    var body: some View {
        // 小螃蟹放在正中间，字在它下面
        VStack(spacing: 10) {
            Spacer()
            RoamingCrab(working: .idle, roams: false, pixel: 10.0 / 3, typing: typing, cue: cue)
                // 拎到下面去的时候压在问候和快捷开头上面，不被挡住
                .zIndex(1)
            Text("\(greeting), \(name)")
                .font(Theme.greetingFont(22))
                .foregroundStyle(Theme.textPrimary)
            if let projectName {
                Label(projectName, systemImage: "folder")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 0.6))
            }
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(starters, id: \.text) { item in
                        Button {
                            onStarter(item.text)
                        } label: {
                            Label(item.text, systemImage: item.icon)
                                .font(.subheadline)
                                .lineLimit(1)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 白底细边的圆按钮
struct CircleButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// The composer still has a phone button. This package does not use the microphone.
struct VoiceCallNotice: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Voice calls are not part of this package.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle("Call")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}
