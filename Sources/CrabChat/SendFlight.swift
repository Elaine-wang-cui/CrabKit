import Observation
import SwiftUI
import UIKit

/// Timing marks stay in the call sites and do nothing here, so a flight
/// never prints message text or a private subsystem name.
enum SendMark {
    static func event(_ name: @autoclosure () -> String) {}

    enum Signpost {
        static func beginPane() {}
        static func endPane() {}
        static func beginCommit() {}
        static func endCommit() {}
        static func beginHost() {}
        static func endHost() {}
        static func caCommit() {}
        static func beginAfterInsert() {}
        static func endAfterInsert() {}
        static func beginScrollLayout() {}
        static func endScrollLayout() {}
    }

    static func body(_ name: @autoclosure () -> String, seconds: Double) {}
}

enum SendFlightTrace {
    static func log(_ message: @autoclosure () -> String, every interval: TimeInterval = 0) {}
}

/// Flight bookkeeping. ChatView never reads the live destination, so a moving copy
/// does not rebuild the composer or write back into the field.
@Observable
final class SendFlightModel {
    var composerFrame: CGRect = .zero
    var columnWidth: CGFloat = 0
    var destination: CGRect = .zero
    var atBottom = true
    /// Bumped when the transcript should glide to the latest row.
    var scrollCommand = 0
    /// A long trip back from somewhere up the history, not a one-row follow.
    var scrollFast = false
    /// True while a programmatic scroll is still moving the list.
    private(set) var scrollActive = false
    /// True only for an at-bottom send whose list may have to catch up by several rows.
    /// Rapid-send follows and the long "scrolled up" glide leave this off.
    private(set) var allowCatchUp = false
    /// The catch-up ease is running, so the copy follows the live row instead of the takeoff guess.
    private(set) var trackRow = false
    /// Set when a finger takes the list. Gentle follows refuse to start again until the next send.
    static var userHeldList = false
    /// Keyboard is up, from a measured composer frame, and the row's center is still under it.
    /// The scroll link reads this. `keyboardLift` is the observed copy the flight view reads.
    static var rowUnderKeyboard = false
    /// How far the in-chat scroller still has to travel, in points. The copy aims at the
    /// live row shifted by this, so it does not assume a reply height. 0 once the glide is done.
    static var scrollRemain: CGFloat = 0
    /// Built row frames in the scroll's content coordinates. Only rows SwiftUI has laid out.
    static var rowSpots: [RowContentSpot] = []
    /// The transcript's last message. The padding below it counts as covered.
    static var lastRowID: UUID?
    /// When the newest insert returned. The quiet wait is measured from here.
    static var insertedAt: CFTimeInterval = 0
    /// True once this send's glide has had a real gap, so a later zero means it finished.
    static var scrollMoved = false
    /// True after this send's list has reported a gap, including a gap of zero.
    static var scrollSampled = false
    /// Model content offset. The row probe is measured against `geometryOffset`.
    static var modelOffset: CGFloat = .nan
    /// Content offset at the last flight-space row frame.
    static var geometryOffset: CGFloat = .nan
    /// A coast-end write is waiting for the first row-frame log.
    static var coastWritePending = false
    /// The finger is down. A drag reveals when it lifts, not at the copy's fallback.
    static var listFingerDown = false
    /// D1/deep. The aim stays provisional until this send has seen the bottom marker
    /// and the content height has been still after that.
    static var longGlide = false
    static var contentSettled = true
    /// The bottom marker appeared during this send. Reset in `claim`.
    static var bottomSeenThisSend = false
    /// While a deep glide is running, only the tail row needs a probe.
    var probeAll = true
    /// Offset that puts the user row on the frozen aim, plus the content top it was locked to.
    static var lockedFinalOffset: CGFloat = .nan
    static var lockedContentTop: CGFloat = .nan
    /// New rows expected at the tap, before they exist. The list plans from this plus the gap already on screen.
    static var plannedAdd: CGFloat = 120
    /// A scrolled-up trip long enough that the copy must stay until it is actually on the row.
    static var deepTrip = false
    /// How long the in-chat copy may follow before a non-deep send gives up.
    static var copyLimit: TimeInterval = 1.2
    /// Ease length for the copy, matched to the list plan.
    static var flightSpan: TimeInterval = 0.44
    /// The in-chat copy's Core Animation leg has been committed to the render server.
    static var coastFlushed = false
    /// Media time of the newest tap. Deadlines are measured from here, not from the first tick after the insert.
    static var tapTime: CFTimeInterval = 0
    /// Absolute media time the copy and the list are aiming to arrive.
    /// The list overwrites this with its real projected landing once the plan exists.
    static var arriveAt: CFTimeInterval = 0
    /// Highest generation whose insert has returned. A newer claim does not clear it,
    /// so the previous glide keeps moving while the new send waits.
    static var insertedGeneration = 0
    /// Generation of the send in `claim`. `finish()` bumps `generation` without an insert;
    /// scroll and the copy follow this number instead.
    static var currentGeneration = 0

    static func noteInserted(_ generation: Int) {
        if generation > insertedGeneration {
            insertedGeneration = generation
            insertedAt = CACurrentMediaTime()
        }
    }

    /// Near trips meet the row just after 0.42s. Longer trips use the list's deadline.
    static func noteTrip(_ distance: CGFloat) {
        let base = tapTime > 0 ? tapTime : CACurrentMediaTime()
        let horizon: CFTimeInterval
        if distance > 2000 || deepTrip {
            horizon = 1.0
        } else if distance > 700 {
            horizon = 0.60
        } else if distance > 144 {
            horizon = 0.50
        } else {
            horizon = 0.44
        }
        arriveAt = base + horizon
        flightSpan = horizon
    }
    fileprivate static weak var reporting: SendFlightModel?

    /// Stop probing every row. Called from the list once a deep plan is running.
    static func dropRowProbes() {
        reporting?.probeAll = false
    }
    private(set) var keyboardLift = false

    /// Composer window frame is measured and sitting well above the screen bottom.
    var keyboardUp: Bool {
        guard composerWindow.isSendFrame, composerFrame.minY > 1 else { return false }
        return UIScreen.main.bounds.height - composerWindow.maxY > 140
    }
    /// Observable mirror of `userHeldList`, so the row can leave opacity 0 when a flick starts.
    private(set) var listHeld = false
    private(set) var generation = 0
    private(set) var ticket: SendTicket?
    private(set) var userID: UUID?
    private(set) var started: Date?
    /// False while the copy is still aimed at a guess (empty chat, before the row exists).
    private(set) var hasRealDestination = false
    /// The row is visible and the copy is fading off it. Not a one-frame swap.
    private(set) var revealing = false
    /// Window-level copy. Only the first send, before a transcript exists.
    private(set) var usesWindow = false
    /// Composer text box in window coordinates, for that first flight only.
    var composerWindow: CGRect = .zero
    private var didAskScroll = false

    var ticketID: UUID? { ticket?.id }
    /// The row the copy is standing in for. Nil when there is no copy, so the anchor stays off.
    var flightUserID: UUID? { ticket == nil ? nil : userID }

    /// Always returns a ticket when there is something to send, so a rapid follow-up still flies.
    /// A copy already on screen is dropped. This does not write the draft.
    func claim(text: String, files: [Attachment], origin: CGRect, wasAtBottom: Bool, windowFlight: Bool = false) -> SendTicket? {
        let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shown.isEmpty || !files.isEmpty else { return nil }
        if ticket != nil { clear() }
        // A send is never delayed by a flight. The caller already captured and cleared the draft.
        Self.userHeldList = false
        Self.listFingerDown = false
        Self.geometryOffset = .nan
        Self.coastWritePending = false
        Self.longGlide = false
        Self.contentSettled = true
        Self.bottomSeenThisSend = wasAtBottom
        Self.lockedFinalOffset = .nan
        Self.lockedContentTop = .nan
        probeAll = true
        // Keyboard-up rows have to climb. Start the 12pt lift with the flight,
        // not after the row's frame is measured, or the copy arrives and waits.
        Self.rowUnderKeyboard = keyboardUp
        keyboardLift = keyboardUp
        Self.scrollRemain = 0
        Self.scrollMoved = false
        Self.scrollSampled = false
        Self.deepTrip = false
        Self.copyLimit = 1.2
        Self.flightSpan = 0.44
        Self.coastFlushed = false
        let now = CACurrentMediaTime()
        Self.tapTime = now
        Self.arriveAt = now + 0.44
        let lines = max(1, ceil(CGFloat(max(shown.count, 1)) / 28))
        var add = min(220, 28 + lines * 22) + 80
        if keyboardUp { add += 90 }
        Self.plannedAdd = add
        Self.reporting = self
        listHeld = false
        generation += 1
        Self.currentGeneration = generation
        usesWindow = windowFlight
        scrollActive = false
        allowCatchUp = false
        trackRow = false
        SendFlightTrace.log("phase=claim window=\(windowFlight) atBottom=\(wasAtBottom) gen=\(generation)")
        SendMark.event("flight.start window=\(windowFlight) gen=\(generation)")
        let ticket = SendTicket(
            id: UUID(),
            text: shown,
            attachments: files,
            wasAtBottom: wasAtBottom,
            origin: origin
        )
        self.ticket = ticket
        destination = .zero
        userID = nil
        // Start the clock now, even if the row does not exist yet, so a cold first
        // launch glides up instead of sitting on the composer until layout finishes.
        started = Date()
        hasRealDestination = false
        revealing = false

        // Every in-chat send starts the glide at the tap, including a short line with
        // the keyboard down. A new chat uses the window copy and does not start this.
        // The request made once the row exists retargets the same glide.
        didAskScroll = false
        if !windowFlight {
            requestScroll(fast: true)
        }
        return ticket
    }

    func attach(userID: UUID) {
        guard ticket != nil else { return }
        self.userID = userID
        // Don't clear started or the guess. The empty-chat copy is already moving;
        // wiping it here is what parked A1 on the field until the new list laid out.
    }

    func noteDestination(_ frame: CGRect) {
        guard ticket != nil, userID != nil, frame.isSendFrame else { return }
        let firstReal = !hasRealDestination
        if firstReal || frame.changed(from: destination) {
            destination = frame
            // The offset stored with this frame. Content top is not sampled here:
            // it arrives in a different callback and must not be mixed in.
            Self.geometryOffset = Self.modelOffset
        }
        hasRealDestination = true
        if firstReal { SendMark.event("flight.target") }
        // A short row at the fold stays on the 6pt creep. Once a tall row is under
        // the keyboard, keep the 12pt step until the bubble has cleared the field.
        if !keyboardUp {
            Self.rowUnderKeyboard = false
            keyboardLift = false
        } else if frame.midY > composerFrame.minY + 36 {
            Self.rowUnderKeyboard = true
            keyboardLift = true
        } else if frame.maxY <= composerFrame.minY - 4 {
            Self.rowUnderKeyboard = false
            keyboardLift = false
        }
        if started == nil {
            started = Date()
        }
        guard firstReal, !didAskScroll else { return }
        didAskScroll = true
        // The window copy is not gated by this list. A zero-distance in-chat glide
        // must not keep the new-chat handoff waiting.
        if usesWindow { return }
        // The rows exist now. Retarget the glide already running, including the
        // at-bottom catch-up. Do not restart it from rest.
        let catchUp = ticket?.wasAtBottom == true
        requestScroll(fast: ticket?.wasAtBottom == false, catchUp: catchUp)
    }

    /// The scroller reports the live gap. A gap under 1.5pt is not scrolling,
    /// even when the watch link is still armed for a later content change.
    static func noteBottom() {
        bottomSeenThisSend = true
    }

    static func noteRowSpots(_ spots: [RowContentSpot], lastID: UUID?) {
        rowSpots = spots
        lastRowID = lastID
    }

    /// Content-space top of the user row the copy is standing in for.
    static func userContentTop() -> CGFloat? {
        guard let id = reporting?.userID else { return nil }
        return rowSpots.first { $0.id == id }?.minY
    }

    /// Flight-space top of the row at the offset that is actually written.
    /// Only the offset stored with this frame is applied. A later content-top
    /// callback is not added on top of a frame that may already include it.
    static func revealedRowY(_ raw: CGFloat) -> CGFloat {
        SendFlightPlan.revealedY(raw: raw, modelOffset: modelOffset, geometryOffset: geometryOffset)
    }

    /// Lock the offset that holds the user row on the aim the copy just froze.
    static func lockAim(remain: CGFloat) {
        guard lockedFinalOffset.isNaN, modelOffset.isFinite else { return }
        lockedContentTop = userContentTop() ?? .nan
        lockedFinalOffset = modelOffset + max(0, remain)
    }

    static func reportScroll(_ distance: CGFloat) {
        scrollRemain = distance
        scrollSampled = true
        if abs(distance) >= 1.5 { scrollMoved = true }
        reporting?.setScrolling(abs(distance) >= 1.5)
    }

    func setScrolling(_ moving: Bool) {
        if scrollActive != moving { scrollActive = moving }
    }

    func requestScroll(fast: Bool, catchUp: Bool = false) {
        // A finger drag wins. Do not start another creep back to the bottom until the next send.
        if Self.userHeldList, !fast { return }
        // A streaming nudge must not cancel the short catch-up ease mid-flight.
        if trackRow, !fast { return }
        // Not scrolling until the scroller measures a real gap. A zero-distance
        // glide must not hold scrollActive for the whole 0.42s clock.
        scrollFast = fast
        // Latch on. scrollDidIdle clears it, so a later text update can't demote the ease.
        if catchUp { allowCatchUp = true }
        scrollCommand += 1
    }

    func scrollDidIdle() {
        scrollActive = false
        // Keep trackRow for the rest of this flight. Clearing it would aim the
        // copy back along the original diagonal while it is already on the row.
        allowCatchUp = false
        if Self.userHeldList {
            listHeld = true
        }
    }

    func beginCatchUp() {
        trackRow = true
        SendFlightTrace.log("scroll catchup track row")
    }

    /// Drop the copy and show the real row. Does not write the composer.
    /// The row fades in over the copy; nothing is replaced in a single frame.
    /// The generation bump invalidates an in-flight land. The save id stays the one from claim.
    func finish() {
        guard ticket != nil, !revealing else { return }
        generation += 1
        beginReveal(generation: generation)
    }

    func land(generation: Int) {
        guard generation == self.generation, ticket != nil, !revealing else { return }
        if usesWindow {
            SendFlightTrace.log("handoff decision window gen=\(generation)")
            // Show the row now, but leave the window copy up. It comes down only
            // after the row has reported opacity 1 and two later display ticks,
            // so the two overlap instead of leaving a blank frame.
            revealing = true
            FlightHost.shared.holdForRow(generation: generation)
            return
        }
        beginReveal(generation: generation)
    }

    private func beginReveal(generation: Int) {
        revealing = true
        SendMark.event("flight.land gen=\(generation)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.clear()
        }
    }

    private func clear() {
        let gen = generation
        ticket = nil
        userID = nil
        started = nil
        destination = .zero
        hasRealDestination = false
        revealing = false
        usesWindow = false
        didAskScroll = false
        allowCatchUp = false
        trackRow = false
        Self.rowUnderKeyboard = false
        keyboardLift = false
        FlightHost.shared.remove(generation: gen)
    }

    /// The window copy has overlapped the opaque row. Drop the ticket now.
    func releaseWindow(generation: Int) {
        guard generation == self.generation, usesWindow else { return }
        clear()
    }

    func showsCopy(of messageID: UUID) -> Bool {
        // A flick unhides the row immediately. Leaving it at opacity 0 while the copy
        // fades is how the last bubble vanished without the row ever painting.
        guard let ticket, !revealing, !listHeld, ticket.origin.isSendFrame, userID == messageID else { return false }
        return true
    }
}

/// Named space covering the transcript and the composer, so a send can read both frames in one system.
enum SendFlightSpace {
    static let name = "chat"
}

struct SendTicket: Equatable {
    let id: UUID
    let text: String
    let attachments: [Attachment]
    var wasAtBottom: Bool
    /// Composer text frame captured before the box was cleared. Not updated while the box shrinks.
    var origin: CGRect
}

enum SendFlightTiming {
    /// One diagonal from the composer to the row. A send ~0.5s later still gets its own flight.
    static let duration: TimeInterval = 0.42
    /// The first insert can stall layout. Let the copy start moving before that, then clear the flag.
    static var deferFirstInsert = true
}

extension CGRect {
    /// A real view frame, not the zero placeholder preferences use.
    var isSendFrame: Bool {
        width > 1 && height > 1 && minX.isFinite && minY.isFinite
    }

    func changed(from other: CGRect) -> Bool {
        abs(minX - other.minX) > 0.5 || abs(minY - other.minY) > 0.5
            || abs(width - other.width) > 0.5 || abs(height - other.height) > 0.5
    }
}

enum RowContentSpace {
    static let name = "rowContent"
    /// `LazyVStack` spacing. Coverage allows this gap, plus a few points of slack.
    static let spacing: CGFloat = 22
    static let spacingSlack: CGFloat = 8
}

struct RowContentSpot: Equatable {
    var id: UUID
    var minY: CGFloat
    var height: CGFloat
}

enum RowContentFramesKey: PreferenceKey {
    static var defaultValue: [RowContentSpot] = []
    static func reduce(value: inout [RowContentSpot], nextValue: () -> [RowContentSpot]) {
        for spot in nextValue() {
            if let index = value.firstIndex(where: { $0.id == spot.id }) {
                value[index] = spot
            } else {
                value.append(spot)
            }
        }
    }
}

struct RowContentProbe: View {
    var id: UUID

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(RowContentSpace.name))
            Color.clear.preference(
                key: RowContentFramesKey.self,
                value: [RowContentSpot(id: id, minY: frame.minY, height: proxy.size.height)]
            )
        }
    }
}

enum ComposerTextFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

enum SendFlightDestKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

enum ColumnWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 1 { value = next }
    }
}

private struct SendFlightTargetKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    /// The user message whose bubble frame should be reported for the send flight.
    var sendFlightTarget: UUID? {
        get { self[SendFlightTargetKey.self] }
        set { self[SendFlightTargetKey.self] = newValue }
    }
}

struct ComposerFrameReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ComposerTextFrameKey.self, value: proxy.frame(in: .named(SendFlightSpace.name)))
                .preference(key: ComposerWindowFrameKey.self, value: proxy.frame(in: .global))
        }
    }
}

enum ComposerWindowFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

enum FlightWindowDestKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

struct ColumnWidthReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ColumnWidthKey.self, value: proxy.size.width)
        }
    }
}

/// Reports the tight user-bubble frame while this row is the one in flight.
struct SendFlightAnchor: View {
    var on: Bool

    var body: some View {
        if on {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SendFlightDestKey.self, value: proxy.frame(in: .named(SendFlightSpace.name)))
                    .preference(key: FlightWindowDestKey.self, value: proxy.frame(in: .global))
            }
        }
    }
}

/// The user's bubble (and pending thumbs), shared by the row and the flying copy so they land on the same pixels.
struct UserBubbleCluster: View {
    let text: String
    var attachments: [Attachment] = []
    var showsMenu: Bool = true
    var onZoom: ((Attachment) -> Void)? = nil
    var session: ChatSession? = nil
    var message: ChatMessage? = nil
    @Environment(\.reading) private var reading

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !attachments.isEmpty {
                attachmentRow
            }
            if !text.isEmpty {
                textBubble
            }
        }
    }

    private var textBubble: some View {
        Text(text)
            .font(reading.body)
            .lineSpacing(reading.lineGap)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.accent.opacity(0.85), lineWidth: 1.3))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contextMenu { if showsMenu { bubbleMenu } }
    }

    @ViewBuilder
    private var bubbleMenu: some View {
        Button {
            UIPasteboard.general.string = text
            Haptics.copied()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        if let session, let message {
            ForkMenuButton(session: session, message: message, title: "Edit and branch from here")
        }
    }

    private var attachmentRow: some View {
        let side: CGFloat = attachments.count == 1 ? 180 : 110
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { thumbItems(side) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { thumbItems(side) }
            }
        }
    }

    private func thumbItems(_ side: CGFloat) -> some View {
        ForEach(attachments) { item in
            if item.kind == .image {
                Button { onZoom?(item) } label: {
                    AttachmentThumb(attachment: item, size: side)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View image")
            } else {
                FileChip(attachment: item)
            }
        }
    }
}

/// A copy of the sent bubble, drawn above the transcript so scroll offset can't drag it.
/// Position is a clock lerp toward whatever frame the row has *this* frame, so a late layout
/// change moves the end point instead of leaving a snap when the real row is revealed.
struct SendFlightBubble: View {
    let text: String
    let attachments: [Attachment]
    let origin: CGRect
    let destination: CGRect
    /// False while `destination` is still the empty-chat guess, not the row.
    let hasRealDestination: Bool
    /// The row is on screen; fade the copy out over the same 0.16s the row fades in.
    let fadeOut: Bool
    /// Bottom of the copy stays above this y (the top of the composer). 0 means no clamp.
    let visibleBottom: CGFloat
    let columnWidth: CGFloat
    /// The user has the list. The copy may follow the row downward to land on it.
    var followDown: Bool = false
    var onLanded: () -> Void
    @State private var landed = false

    private var maxBubbleWidth: CGFloat {
        let column = columnWidth > 1 ? columnWidth : 320
        return max(column - 48, 60)
    }

    /// Bubble chrome sits outside the glyphs. Pull the copy back so the words stay where they were typed.
    /// Thumbs sit above the text, so only a text-only bubble uses this inset.
    private var textPad: CGPoint {
        attachments.isEmpty && !text.isEmpty ? CGPoint(x: 18, y: 14) : .zero
    }

    /// Top-left of the typed words. Does not use the measured bubble size, so a
    /// later layout (44pt placeholder to the real height) cannot drop the takeoff.
    private var textTop: CGPoint {
        CGPoint(x: origin.minX - textPad.x, y: origin.minY - textPad.y)
    }

    /// Right-aligned and clearly above the typed words, so the first frames move
    /// up and right together. A later row only bends this; it does not start the rise.
    private func predictedTop() -> CGPoint {
        let width = min(maxBubbleWidth, max(60, CGFloat(text.count) * 7 + 36))
        let left = origin.maxX - textPad.x - width
        // At or below the lowest measured rest (~145pt). Aiming higher forces a late downward correction.
        let rise: CGFloat = 140
        return CGPoint(x: max(textTop.x, left), y: textTop.y - rise)
    }

    /// Top-left we are flying toward. While the list still has a gap, the row's top
    /// minus that gap is where the row will sit. Once the scroller has finished,
    /// the live top is the aim. Nothing here assumes a reply height.
    private func aimTop() -> CGPoint {
        guard hasRealDestination, destination.isSendFrame else { return predictedTop() }
        if followDown {
            return CGPoint(x: max(textTop.x, destination.minX), y: destination.minY)
        }
        let remain = SendFlightModel.scrollRemain
        let predicted = predictedTop()
        // The row's landing spot, once it exists. `minY - remain` is where that row
        // will sit after the list closes its gap. Stopping on the opening guess
        // parks the copy below the real row.
        let landing = abs(remain) >= 1.5 ? destination.minY - remain : destination.minY
        let x = destination.minX
        let clampedX = x < textTop.x ? textTop.x : x
        // A frame still under the composer is not a landing spot. Keep the rise
        // until the projected spot is above the typed words.
        let clampedY = landing > textTop.y + 4 ? min(predicted.y, textTop.y + 4) : landing
        return CGPoint(x: clampedX, y: clampedY)
    }

    /// One-way x, and at most 4pt downward from the typed words.
    private func limited(_ point: CGPoint) -> CGPoint {
        var point = point
        if point.x < textTop.x { point.x = textTop.x }
        if point.y > textTop.y + 4 { point.y = textTop.y + 4 }
        return point
    }

    var body: some View {
        FlightPlate(
            text: text,
            attachments: attachments,
            textTop: textTop,
            aim: limited(aimTop()),
            maxWidth: maxBubbleWidth,
            row: destination,
            hasRow: hasRealDestination && destination.isSendFrame,
            rowClear: visibleBottom < 1 || !destination.isSendFrame || destination.maxY <= visibleBottom - 4,
            fadeOut: fadeOut,
            onLanded: {
                guard !landed else { return }
                landed = true
                onLanded()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Spread `span` across `frames` at or under `cap`. The first step is at most `opening`.
/// The last three steps fall in the ratio 4:2:1, which is 24, 12, 6 when the cruise is 24.
/// A longer trip that cannot fit under the cap gains frames instead of a step past the cap.
fileprivate func pacedTravel(_ span: CGFloat, frames: Int, cap: CGFloat, opening: CGFloat) -> [CGFloat] {
    guard span > 0.5 else { return [] }
    let opening = min(max(opening, 0), cap)
    var count = max(4, frames)
    func cruiseSpeed(_ count: Int) -> CGFloat {
        let slow = span / (CGFloat(count) - 1.25)
        if slow <= opening { return slow }
        return (span - opening) / max(CGFloat(1), CGFloat(count) - 2.25)
    }
    var cruise = cruiseSpeed(count)
    while cruise > cap + 0.01, count < 90 {
        count += 1
        cruise = cruiseSpeed(count)
    }
    cruise = min(cap, max(cruise, CGFloat(0)))
    let first = min(opening, min(cruise, span))
    var steps: [CGFloat] = [first]
    var left = span - first
    let middle = max(0, count - 4)
    for _ in 0..<middle {
        let step = min(cruise, max(CGFloat(0), left))
        if step <= 0.05 { break }
        steps.append(step)
        left -= step
    }
    guard left > 0.05 else { return steps }
    let weights: [CGFloat] = [4, 2, 1]
    var remain = left
    for (index, weight) in weights.enumerated() {
        let step: CGFloat
        if index == weights.count - 1 {
            step = max(CGFloat(0), remain)
        } else {
            step = min(cap, left * weight / 7.0)
        }
        if step > 0.05 {
            steps.append(step)
            remain -= step
        }
    }
    if remain > 0.05, !steps.isEmpty {
        steps[steps.count - 1] += remain
    }
    // A leftover smaller than a quarter of the previous step is not its own frame.
    // Folding it keeps the coast from dropping 12pt to a fraction and stopping.
    if steps.count >= 2 {
        let last = steps[steps.count - 1]
        let prev = steps[steps.count - 2]
        if last < prev * 0.75, last < 1 {
            steps[steps.count - 2] = prev + last
            steps.removeLast()
        }
    }
    return steps
}

/// Moves the copy on a display link. SwiftUI's timeline was committing only when
/// a layout burst arrived, so the bubble held for several frames and then jumped.
private struct FlightPlate: UIViewRepresentable {
    var text: String
    var attachments: [Attachment]
    var textTop: CGPoint
    var aim: CGPoint
    var maxWidth: CGFloat
    var row: CGRect
    var hasRow: Bool
    var rowClear: Bool
    var fadeOut: Bool
    var onLanded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FlightPlateView {
        let view = FlightPlateView()
        context.coordinator.view = view
        context.coordinator.install(text: text, attachments: attachments, maxWidth: maxWidth)
        return view
    }

    func updateUIView(_ uiView: FlightPlateView, context: Context) {
        let c = context.coordinator
        c.view = uiView
        c.textTop = textTop
        if !c.aimFrozen {
            var next = aim
            if c.aim != .zero, next.y > c.aim.y + 4 {
                next.y = c.aim.y + 4
            }
            if hypot(c.aim.x - next.x, c.aim.y - next.y) > 0.5 {
                SendMark.event(String(format: "copy.aim %.0f,%.0f -> %.0f,%.0f", c.aim.x, c.aim.y, next.x, next.y))
            }
            c.aim = next
        }
        c.maxWidth = maxWidth
        c.row = row
        c.hasRow = hasRow
        c.rowClear = rowClear
        c.onLanded = onLanded
        c.install(text: text, attachments: attachments, maxWidth: maxWidth)
        if fadeOut { c.fade() }
        c.start()
    }

    static func dismantleUIView(_ uiView: FlightPlateView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        weak var view: FlightPlateView?
        var textTop: CGPoint = .zero
        var aim: CGPoint = .zero
        var maxWidth: CGFloat = 280
        var row: CGRect = .zero
        var hasRow = false
        var rowClear = false
        var onLanded: () -> Void = {}
        /// Set once the settled slot is known. The copy stays on this slot.
        var aimFrozen = false
        /// The post-freeze flight is a render-server animation, not a display-link step.
        private var slotFlying = false
        private var link: CADisplayLink?
        private var pos: CGPoint?
        private var began: CFTimeInterval = 0
        private var lastStamp: CFTimeInterval = 0
        /// Advances one frame per callback. Wall time is only for the miss log.
        private var flown: CFTimeInterval = 0
        /// Points per frame the coast was moving when the link took over.
        private var carry: CGFloat = 0
        /// True for the single link frame that follows the coast. Later frames may slow down.
        private var carryArmed = false
        private var framesSeen = 0
        /// Core Animation is driving the opening diagonal while the main thread is in the insert layout.
        private var coasting = false
        private var coastBegan: CFTimeInterval = 0
        /// One entry per coast frame. Paced to the tap, with a 4:2:1 tail.
        private var coastSteps: [CGFloat] = []
        /// `arriveAt` this coast was built for. A later deadline rebuilds it.
        private var coastDeadline: CFTimeInterval = 0
        private var lastCoastRebuild: CFTimeInterval = 0
        /// Slot change seen on this many ticks in a row. A one-tick blip does not retarget.
        private var slotCandidate = CGPoint.zero
        private var slotCandidateTicks = 0
        private var lastSlotRebuild: CFTimeInterval = 0
        /// The send this plate belongs to. A later send must not end this coast early.
        private var flightGeneration = 0
        private var landed = false
        private var fading = false
        private var didInstall = false
        private var measures = 0
        private var lastMark: CFTimeInterval = 0
        /// One line per flight, once the list has settled or the copy is on the row.
        private var meetLogged = false
        /// Row top and gap from the last sample that still had the list moving.
        /// A remain of zero before this top moves is the pre-scroll frame, not the landing.
        private var anchoredRowY: CGFloat = .nan
        private var anchoredRemain: CGFloat = 0
        /// True when this tick's row frame has not caught the offset write yet.
        private var rowStale = false

        func install(text: String, attachments: [Attachment], maxWidth: CGFloat) {
            guard let view, !didInstall else { return }
            didInstall = true
            view.host.rootView = AnyView(
                UserBubbleCluster(text: text, attachments: attachments, showsMenu: false)
                    .frame(maxWidth: maxWidth, alignment: .trailing)
                    .fixedSize()
            )
            measure()
        }

        private func measure() {
            guard let view, measures < 4 else { return }
            measures += 1
            view.host.view.setNeedsLayout()
            SendMark.Signpost.beginHost()
            view.host.view.layoutIfNeeded()
            SendMark.Signpost.endHost()
            let fit = view.host.view.sizeThatFits(CGSize(width: maxWidth, height: 2000))
            guard fit.width > 1, fit.height > 1 else { return }
            view.fitted = CGSize(width: min(maxWidth, fit.width), height: fit.height)
        }

        func fade() {
            guard let view, !fading else { return }
            fading = true
            UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                view.host.view.alpha = 0
            }
        }

        /// Put the copy on the typed words before the first display, so it never flashes at the origin.
        func placeAtStart() {
            guard let view else { return }
            if pos == nil { pos = textTop }
            let origin = pos ?? textTop
            let size = view.fitted
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.host.view.frame = CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
            if !fading {
                view.host.view.alpha = 1
                view.host.view.isHidden = false
            }
            CATransaction.commit()
        }

        func start() {
            guard !landed else { return }
            guard link == nil else { return }
            placeAtStart()
            flightGeneration = SendFlightModel.currentGeneration
            anchoredRowY = .nan
            anchoredRemain = 0
            rowStale = false
            meetLogged = false
            beginCoast()
            began = CACurrentMediaTime()
            lastStamp = 0
            flown = 0
            SendMark.event("copy.link")
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = 60
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        /// Opening diagonal while the main thread is in the insert layout.
        /// Steps are the distance left divided by the frames until the near-bottom
        /// deadline, capped at 24. The first step stays at most 12, and the end tapers.
        /// The transaction is flushed later, after this SwiftUI update returns.
        private func beginCoast() {
            guard let view else { return }
            let size = view.fitted
            let origin = pos ?? textTop
            let from = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
            let to = CGPoint(x: aim.x + size.width / 2, y: aim.y + size.height / 2)
            let span = hypot(to.x - from.x, to.y - from.y)
            guard span > 1 else {
                SendFlightModel.coastFlushed = true
                return
            }
            let ux = (to.x - from.x) / span
            let uy = (to.y - from.y) / span
            let horizon = max(0.20, SendFlightModel.arriveAt - CACurrentMediaTime())
            let frameCount = max(8, Int((horizon * 60).rounded(.up)))
            coastSteps = pacedTravel(span, frames: frameCount, cap: 24, opening: 12)
            var dist: CGFloat = 0
            var values: [CGPoint] = [from]
            for step in coastSteps {
                dist = min(span, dist + step)
                values.append(CGPoint(x: from.x + ux * dist, y: from.y + uy * dist))
                if dist >= span - 0.5 { break }
            }
            let slots = max(values.count - 1, 1)
            let times: [NSNumber] = (0...slots).map { NSNumber(value: Double($0) / Double(slots)) }
            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.values = values.map { NSValue(cgPoint: $0) }
            anim.keyTimes = times
            anim.duration = CFTimeInterval(times.count - 1) / 60.0
            anim.calculationMode = .linear
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            view.host.view.layer.add(anim, forKey: "coast")
            coasting = true
            coastBegan = CACurrentMediaTime()
            coastDeadline = SendFlightModel.arriveAt
            lastCoastRebuild = coastBegan
            SendFlightModel.coastFlushed = true
            SendMark.event(String(format: "copy.coast %.0f,%.0f -> %.0f,%.0f", from.x, from.y, to.x, to.y))
        }

        /// How far the coast moves in the frame at `age`.
        private func coastStep(at age: CFTimeInterval) -> CGFloat {
            guard !coastSteps.isEmpty else { return 12 }
            let index = min(coastSteps.count - 1, max(0, Int((age * 60).rounded(.down))))
            return coastSteps[index]
        }

        /// The model layer is still at the start. The drawn position is the presentation layer.
        private func endCoast() {
            guard let view else { coasting = false; return }
            let size = view.fitted
            let presented = view.host.view.layer.presentation()?.position
                ?? CGPoint(x: (pos ?? textTop).x + size.width / 2, y: (pos ?? textTop).y + size.height / 2)
            let topLeft = CGPoint(x: presented.x - size.width / 2, y: presented.y - size.height / 2)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.host.view.layer.position = presented
            view.host.view.layer.removeAnimation(forKey: "coast")
            view.host.view.frame = CGRect(origin: topLeft, size: size)
            CATransaction.commit()
            pos = topLeft
            let age = max(0, CACurrentMediaTime() - coastBegan)
            flown = age
            carry = coastStep(at: age)
            carryArmed = true
            coasting = false
            SendMark.event(String(format: "copy.coast end x=%.0f y=%.0f", topLeft.x, topLeft.y))
            SendMark.event(String(format: "copy.handoff x=%.0f y=%.0f v=%.0f t=%.3f", topLeft.x, topLeft.y, carry, flown))
        }

        /// Where the row will sit once the list has settled. Nil until the row exists
        /// and this send's scroll gap has been measured, and the slot is above the composer.
        /// `scrollRemain` is the model gap, so this stays put while a coast only moves the presentation.
        /// A remain of zero while the row top is still the pre-scroll one keeps that prediction.
        private func measuredSlot() -> CGPoint? {
            guard hasRow, row.isSendFrame, SendFlightModel.scrollSampled else { return nil }
            let remain = SendFlightModel.scrollRemain
            let shownY = SendFlightModel.revealedRowY(row.minY)
            let sample = SendFlightPlan.slotY(
                rowY: shownY,
                remain: remain,
                anchoredRow: anchoredRowY,
                anchoredRemain: anchoredRemain
            )
            rowStale = sample.stale
            if abs(remain) >= 1.5 {
                anchoredRowY = shownY
                anchoredRemain = remain
            } else if !sample.stale {
                anchoredRowY = shownY
                anchoredRemain = 0
            }
            if sample.y > textTop.y + 4 { return nil }
            return CGPoint(x: max(textTop.x, row.minX), y: sample.y)
        }

        /// Downward aim changes stay at or under 4pt a frame. Upward retargets are free.
        private func lowered(_ slot: CGPoint) -> CGPoint {
            var y = slot.y
            if aim != .zero, y > aim.y + 4 { y = aim.y + 4 }
            return CGPoint(x: max(textTop.x, slot.x), y: y)
        }

        /// Positions from `from` toward `to`, starting one step ahead. The first step stays
        /// within a quarter of `speed` when the copy is already moving. Each step obeys the
        /// copy's axis caps, so a rebuild cannot jump from 6pt to 24pt or sink.
        private func limitedSteps(from: CGPoint, to: CGPoint, speed: CGFloat, frames: Int) -> [CGPoint] {
            var p = from
            var points: [CGPoint] = []
            var left = max(1, frames)
            var opening = true
            while points.count < 90 {
                let dx = to.x - p.x
                let dy = to.y - p.y
                let dist = hypot(dx, dy)
                if dist <= 0.5 {
                    if points.isEmpty { points.append(to) }
                    break
                }
                var pace = dist / CGFloat(left)
                if opening {
                    if speed > 0.5 {
                        pace = min(max(pace, speed * 0.75), speed * 1.25)
                    } else {
                        pace = min(pace, 12)
                    }
                    opening = false
                }
                pace = min(pace, dist)
                var sx = dx / dist * pace
                var sy = dy / dist * pace
                if sx > 24 { sx = 24 }
                if sx < -12 { sx = -12 }
                if sy > 4 { sy = 4 }
                if sy < -24 { sy = -24 }
                if abs(sx) < 0.01, abs(sy) < 0.01 { break }
                let step = hypot(sx, sy)
                if step >= dist - 0.05 {
                    points.append(to)
                    break
                }
                p.x += sx
                p.y += sy
                points.append(p)
                left = max(1, left - 1)
            }
            return points
        }

        /// The rest of the flight, on the render server, so a main-thread stall cannot park it.
        /// The first value is one step ahead of the presentation position, at the current speed.
        private func installSlotFlight() {
            guard let view else { return }
            let now = CACurrentMediaTime()
            lastSlotRebuild = now
            let size = view.fitted
            var from = pos ?? textTop
            if let presented = view.host.view.layer.presentation()?.position {
                from = CGPoint(x: presented.x - size.width / 2, y: presented.y - size.height / 2)
            }
            let speed = max(carry, 0)
            let frames = max(4, Int((max(1.0 / 60.0, SendFlightModel.arriveAt - now) * 60).rounded(.up)))
            let points = limitedSteps(from: from, to: aim, speed: speed, frames: frames)
            guard let first = points.first else {
                slotFlying = false
                return
            }
            if let step = points.first {
                carry = hypot(step.x - from.x, step.y - from.y)
            }
            pos = first
            var values = points.map { CGPoint(x: $0.x + size.width / 2, y: $0.y + size.height / 2) }
            if values.count == 1 {
                values.append(values[0])
            }
            let slots = max(values.count - 1, 1)
            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.values = values.map { NSValue(cgPoint: $0) }
            anim.keyTimes = (0...slots).map { NSNumber(value: Double($0) / Double(slots)) }
            anim.duration = CFTimeInterval(slots) / 60.0
            anim.calculationMode = .linear
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.host.view.layer.position = values[0]
            view.host.view.layer.removeAnimation(forKey: "slot")
            view.host.view.layer.removeAnimation(forKey: "coast")
            view.host.view.frame = CGRect(origin: first, size: size)
            view.host.view.layer.add(anim, forKey: "slot")
            CATransaction.commit()
            coasting = false
            slotFlying = true
            coastDeadline = SendFlightModel.arriveAt
            SendMark.event(String(format: "copy.slot %.0f,%.0f -> %.0f,%.0f frames=%d v=%.1f", from.x, from.y, aim.x, aim.y, slots, carry))
        }

        /// The pre-row keyframe is still the opening coast. Stretch it when the list's
        /// deadline moves later, so a deep copy does not arrive and then wait.
        private func keepPreRowFlight() {
            let want = SendFlightModel.arriveAt
            let now = CACurrentMediaTime()
            guard coasting, abs(want - coastDeadline) > 1.0 / 60.0, now - lastCoastRebuild > 2.0 / 60.0 else { return }
            guard let view else { return }
            let size = view.fitted
            var from = pos ?? textTop
            if let presented = view.host.view.layer.presentation()?.position {
                from = CGPoint(x: presented.x - size.width / 2, y: presented.y - size.height / 2)
            }
            let speed = coastStep(at: max(0, now - coastBegan))
            let frames = max(4, Int((max(1.0 / 60.0, want - now) * 60).rounded(.up)))
            let points = limitedSteps(from: from, to: aim, speed: speed, frames: frames)
            guard let first = points.first else { return }
            var cursor = from
            coastSteps = points.map { point in
                let step = hypot(point.x - cursor.x, point.y - cursor.y)
                cursor = point
                return step
            }
            var values = points.map { CGPoint(x: $0.x + size.width / 2, y: $0.y + size.height / 2) }
            if values.count == 1 { values.append(values[0]) }
            let slots = max(values.count - 1, 1)
            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.values = values.map { NSValue(cgPoint: $0) }
            anim.keyTimes = (0...slots).map { NSNumber(value: Double($0) / Double(slots)) }
            anim.duration = CFTimeInterval(slots) / 60.0
            anim.calculationMode = .linear
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.host.view.layer.position = values[0]
            view.host.view.layer.removeAnimation(forKey: "coast")
            view.host.view.frame = CGRect(origin: first, size: size)
            view.host.view.layer.add(anim, forKey: "coast")
            CATransaction.commit()
            pos = first
            carry = hypot(first.x - from.x, first.y - from.y)
            coastBegan = now
            coastDeadline = want
            lastCoastRebuild = now
            SendMark.event(String(format: "copy.coast retarget %.0f,%.0f -> %.0f,%.0f frames=%d", from.x, from.y, aim.x, aim.y, slots))
        }

        /// Freeze once the settled slot is known. A one-tick blip waits for a second sample.
        /// A real drop, from the content shrinking under the row, retargets on the next frame.
        /// The drawn step stays inside the copy caps; the aim itself is the live slot.
        private func considerSlot() {
            guard let slot = measuredSlot() else { return }
            if !aimFrozen {
                // The tail's real height arrives when it is first built. Freezing
                // before that locks a high aim the list cannot scroll up to.
                if SendFlightModel.longGlide, !SendFlightModel.contentSettled {
                    return
                }
                let next = lowered(slot)
                aim = next
                aimFrozen = true
                slotCandidate = slot
                slotCandidateTicks = 0
                SendMark.event(String(format: "copy.aim freeze %.0f,%.0f", aim.x, aim.y))
                installSlotFlight()
                if SendFlightModel.longGlide {
                    SendFlightModel.lockAim(remain: SendFlightModel.scrollRemain)
                }
                return
            }
            let shownY = SendFlightModel.revealedRowY(row.minY)
            let outside = !rowStale && hasRow && row.isSendFrame && (shownY < aim.y - 12 || shownY > aim.y + 2)
                && abs(SendFlightModel.scrollRemain) < 1.5
            let moved = hypot(slot.x - aim.x, slot.y - aim.y) > 2 || outside
            guard moved else {
                slotCandidateTicks = 0
                return
            }
            if hypot(slot.x - slotCandidate.x, slot.y - slotCandidate.y) <= 2 {
                slotCandidateTicks += 1
            } else {
                slotCandidate = slot
                slotCandidateTicks = 1
            }
            if SendFlightModel.lockedFinalOffset.isNaN, SendFlightModel.contentSettled {
                SendFlightModel.lockAim(remain: SendFlightModel.scrollRemain)
            }
            // While the list is still closing a long gap it can lift the row onto the aim.
            // Once it has stopped, a high aim has to follow or the copy waits out the fallback.
            if slot.y > aim.y + 2, SendFlightModel.longGlide, SendFlightModel.scrollRemain > 12 {
                slotCandidateTicks = 0
                return
            }
            guard slotCandidateTicks >= 2 else { return }
            let now = CACurrentMediaTime()
            guard now - lastSlotRebuild > 2.0 / 60.0 else { return }
            let next = lowered(slot)
            guard hypot(next.x - aim.x, next.y - aim.y) > 0.5 else { return }
            SendMark.event(String(format: "copy.aim refreeze %.0f,%.0f -> %.0f,%.0f", aim.x, aim.y, next.x, next.y))
            aim = next
            installSlotFlight()
        }

        func stop() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let view, !landed else { return }
            let now = link.targetTimestamp
            let wall = lastStamp > 0 ? now - lastStamp : link.duration
            lastStamp = now
            // The link is often added before the insert's frame signal. Ending the
            // coast on that tick puts the copy back on the main thread, and the
            // post-insert layout then freezes it. Leave the render-server coast
            // alone until commitSend has returned.
            if SendFlightModel.insertedGeneration < flightGeneration {
                if coasting {
                    keepPreRowFlight()
                    SendMark.event(String(format: "copy.coasting dt=%.0fms", wall * 1000))
                }
                return
            }
            if !coasting { measure() }
            // Stay on the render-server leg until the row's slot is measured.
            // Ending it here is the park before the row exists.
            let tailOpen = SendFlightModel.longGlide && !SendFlightModel.contentSettled
            if coasting, measuredSlot() == nil || tailOpen {
                keepPreRowFlight()
                let size = view.fitted
                if let presented = view.host.view.layer.presentation()?.position {
                    pos = CGPoint(x: presented.x - size.width / 2, y: presented.y - size.height / 2)
                }
                noteLanding(at: pos ?? textTop, now: now)
                return
            }
            // The first tick after the slot is known takes the presentation position.
            // Carry that speed for this frame only.
            let handed = coasting
            if coasting { endCoast() }
            considerSlot()
            if slotFlying {
                if abs(SendFlightModel.arriveAt - coastDeadline) > 1.0 / 60.0,
                   now - lastSlotRebuild > 2.0 / 60.0 {
                    installSlotFlight()
                }
                let size = view.fitted
                if let presented = view.host.view.layer.presentation()?.position {
                    pos = CGPoint(x: presented.x - size.width / 2, y: presented.y - size.height / 2)
                }
                let p = pos ?? textTop
                noteLanding(at: p, now: now)
                return
            }
            // One displayed step. A long callback does not multiply it.
            flown += max(wall, 1.0 / 60.0)
            var p = pos ?? textTop
            let remainDist = hypot(aim.x - p.x, aim.y - p.y)
            let framesLeft = max(1.0, (SendFlightModel.arriveAt - CACurrentMediaTime()) * 60)
            // Cruise is remain/(framesLeft-1), which leaves exactly two cruise-steps
            // for the last three frames. Those frames split that leftover 3:2:1
            // (R/2, R/3, R/6) and close on the deadline frame.
            let tail = framesLeft <= 3.05
            var pace: CGFloat
            if !tail {
                pace = remainDist / max(1.0, framesLeft - 1.0)
            } else {
                let slots = min(3, max(1, Int(framesLeft.rounded(.up))))
                if slots >= 3 {
                    pace = remainDist / 2
                } else if slots == 2 {
                    pace = remainDist * 2 / 3
                } else {
                    pace = remainDist
                }
            }
            pace = min(24, pace)
            if !handed, framesSeen == 0 { pace = min(12, pace) }
            // A handoff faster than the distance allows would land early. Drop toward
            // the pace instead of holding three quarters of that speed. Never step up.
            let tooFast = carry > pace + 0.05 && carry * CGFloat(framesLeft) > remainDist + 0.5
            if carry > pace, !tail, !tooFast {
                let slowed = carryArmed ? min(24, carry) : max(pace, carry * 0.75)
                pace = min(24, slowed)
            }
            carryArmed = false
            // Last frames, and a handoff that would land early, never step up.
            // The deadline frame still takes whatever is left, so the gap closes.
            let closing = tail && framesLeft <= 1.05
            if !closing, carry > 0.05, tail || tooFast || framesLeft <= 4.05 {
                pace = min(pace, carry)
            }
            if !closing, remainDist <= 0.5, pace <= 0.5 {
                pace = 0
            } else if pace > remainDist {
                pace = remainDist
            }
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if remainDist > 0.05, pace > 0 {
                dx = (aim.x - p.x) / remainDist * pace
                dy = (aim.y - p.y) / remainDist * pace
            }
            func capCopyAxes() {
                if dx > 24 { dx = 24 }
                if dx < -12 { dx = -12 }
                if dy > 4 { dy = 4 }
                if dy < -24 { dy = -24 }
            }
            capCopyAxes()
            var mag = hypot(dx, dy)
            framesSeen += 1
            // Re-apply the quarter-step floor after the axis caps, so a cap cannot
            // turn a 12pt coast into a near-stop while the row is still ahead.
            // The caps apply again afterwards: the rescale must not open dy past 4.
            if !tail, !tooFast, remainDist > 1, carry > mag, !handed || framesSeen > 1 {
                let floor = max(mag, min(remainDist, carry * 0.75))
                if floor > mag, mag > 0 {
                    dx *= floor / mag
                    dy *= floor / mag
                    mag = floor
                }
            }
            capCopyAxes()
            mag = hypot(dx, dy)
            carry = mag
            SendMark.event(String(format: "copy.tick x=%.1f y=%.1f aim=%.1f,%.1f step=%.1f row=%.1f,%.1f", p.x, p.y, aim.x, aim.y, mag, row.minX, row.minY))
            p.x += dx
            p.y += dy
            pos = p
            let size = view.fitted
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.host.view.frame = CGRect(x: p.x, y: p.y, width: size.width, height: size.height)
            if !fading {
                view.host.view.isHidden = false
                view.host.view.alpha = 1
            }
            CATransaction.commit()
            noteLanding(at: p, now: now)
        }

        /// Fade only once the row has reached the frozen slot, or gone past it.
        /// x uses the same clamp as the aim, so a full-width bubble can match.
        private func noteLanding(at p: CGPoint, now: CFTimeInterval) {
            let rowX = max(textTop.x, row.minX)
            let aimX = max(textTop.x, aim.x)
            let xOK = abs(rowX - aimX) <= 2
            // Within a band: a 12pt frame can pass a 2pt window, but a row well above
            // the aim is not arrived. That case retargets instead of cross-fading.
            let revealY = SendFlightModel.revealedRowY(row.minY)
            if SendFlightModel.coastWritePending {
                SendFlightModel.coastWritePending = false
                let content = SendFlightModel.userContentTop() ?? -1
                SendMark.event(String(format: "copy.rowframe raw=%.1f content=%.1f offset=%.1f reveal=%.1f", row.minY, content, SendFlightModel.modelOffset, revealY))
            }
            let yOK = hasRow && row.isSendFrame && revealY >= aim.y - 12 && revealY <= aim.y + 2
            let gap = hypot(p.x - rowX, p.y - revealY)
            let copyThere = abs(p.x - aim.x) <= 2 && p.y >= aim.y - 12 && p.y <= aim.y + 2
            let elapsed = now - began
            let fingerUp = SendFlightModel.userHeldList && !SendFlightModel.listFingerDown
            let onRow = hasRow && row.isSendFrame && xOK && yOK && copyThere
            // A coast-end probe can still sit under the composer while the written
            // offset has already put that row on screen.
            let probedClear = rowClear || abs(revealY - row.minY) > 12
            let close = aimFrozen && probedClear && onRow
            let dragDone = fingerUp && onRow
            let giveUp = elapsed >= SendFlightModel.copyLimit
            let listSettled = SendFlightModel.scrollMoved && abs(SendFlightModel.scrollRemain) < 1.5
            if !meetLogged, hasRow, row.isSendFrame, !rowStale, listSettled || close || dragDone {
                meetLogged = true
                SendMark.event(String(format: "copy.meet gap=%.1f dy=%.1f aim=%.1f raw=%.1f reveal=%.1f remain=%.1f", gap, p.y - revealY, aim.y, row.minY, revealY, SendFlightModel.scrollRemain))
            }
            if !close && !dragDone && !giveUp {
                SendMark.event(String(format: "copy.land refuse row=%d clear=%d gap=%.1f atSlot=%d x=%d frozen=%d stale=%d", hasRow && row.isSendFrame ? 1 : 0, rowClear ? 1 : 0, gap, yOK ? 1 : 0, xOK ? 1 : 0, aimFrozen ? 1 : 0, rowStale ? 1 : 0))
            }
            if close || dragDone || giveUp {
                let override = abs(revealY - row.minY) > 12
                SendMark.event(String(format: "copy.reveal gap=%.1f aim=%.1f,%.1f raw=%.1f reveal=%.1f clear=%d override=%d remain=%.1f stale=%d close=%d", gap, aim.x, aim.y, row.minY, revealY, rowClear ? 1 : 0, override ? 1 : 0, SendFlightModel.scrollRemain, rowStale ? 1 : 0, (close || dragDone) ? 1 : 0))
                fade()
            }
            if ((close || dragDone) && (elapsed >= 0.38 || fingerUp)) || elapsed >= SendFlightModel.copyLimit {
                landed = true
                stop()
                onLanded()
            }
        }
    }
}

private final class FlightPlateView: UIView {
    let host = UIHostingController(rootView: AnyView(EmptyView()))
    var fitted: CGSize = CGSize(width: 44, height: 36)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.safeAreaRegions = []
        host.view.isHidden = true
        host.view.alpha = 0
        host.view.frame = CGRect(origin: .zero, size: fitted)
        addSubview(host.view)
    }

    required init?(coder: NSCoder) { nil }
}

/// The flying copy. Reads the model itself, so destination ticks don't rebuild ChatView or the field.
struct SendFlightLayer: View {
    var pop: SendFlightModel

    var body: some View {
        ZStack {
            if let ticket = pop.ticket, !pop.usesWindow {
                flying(ticket, generation: pop.generation, fadeOut: pop.revealing)
            }
        }
        .allowsHitTesting(false)
        .task(id: pop.generation) { await watchCopy() }
    }

    /// One sleep, not a poll. A cancelled wait returns immediately so the
    /// next send cannot inherit a multi-second stall on the main thread.
    /// The window copy keeps its 2.5s bound. An in-chat copy waits out the
    /// list's plan, which is 2.0s on a deep trip, then fades over 0.16s.
    private func watchCopy() async {
        let generation = pop.generation
        let window = pop.usesWindow
        if window {
            do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
            if Task.isCancelled || pop.generation != generation || pop.revealing { return }
            pop.land(generation: generation)
            return
        }
        do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
        if Task.isCancelled || pop.generation != generation || pop.revealing { return }
        let hold = max(0, Int(SendFlightModel.copyLimit * 1000) - 80)
        do {
            try await Task.sleep(for: .milliseconds(hold))
        } catch {
            return
        }
        if Task.isCancelled || pop.generation != generation || pop.revealing { return }
        if !window, pop.listHeld, pop.ticket != nil, !pop.revealing {
            do {
                try await Task.sleep(for: .milliseconds(1200))
            } catch {
                return
            }
            if Task.isCancelled || pop.generation != generation { return }
        }
        pop.land(generation: generation)
    }

    private func flying(_ ticket: SendTicket, generation: Int, fadeOut: Bool) -> some View {
        SendFlightBubble(
            text: ticket.text,
            attachments: ticket.attachments,
            origin: ticket.origin,
            destination: pop.destination,
            hasRealDestination: pop.hasRealDestination,
            fadeOut: fadeOut,
            visibleBottom: pop.composerFrame.minY,
            columnWidth: pop.columnWidth,
            followDown: pop.listHeld,
            onLanded: { pop.land(generation: generation) }
        )
        .id(ticket.id)
    }
}

/// A send scrolls on one ease decided at the tap. A discontinuity is not part of that ease.
/// A step the curve itself takes may pass 12pt; a discontinuity may not.
struct GentleBottomScroll: UIViewRepresentable {
    var command: Int
    var generation: Int
    var fast: Bool
    var allowCatchUp: Bool
    /// When the flying copy must be on the row. The list uses the same ease-out and finishes with it.
    var deadline: Date?
    var onIdle: () -> Void = {}
    var onCatchUp: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ClampHost {
        let view = ClampHost()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onLayout = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.hookPan(from: view) }
            coordinator?.clampIfNeeded()
        }
        return view
    }

    func updateUIView(_ view: ClampHost, context: Context) {
        view.onLayout = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.hookPan(from: view) }
            coordinator?.clampIfNeeded()
        }
        context.coordinator.generation = generation
        context.coordinator.allowCatchUp = allowCatchUp
        context.coordinator.deadline = deadline
        context.coordinator.onCatchUp = onCatchUp
        context.coordinator.onIdle = onIdle
        context.coordinator.hookPan(from: view)
        context.coordinator.attach(view)
        guard context.coordinator.command != command else { return }
        context.coordinator.command = command
        guard command > 0 else { return }
        context.coordinator.onIdle = onIdle
        context.coordinator.arm(fast: fast)
    }

    static func dismantleUIView(_ uiView: ClampHost, coordinator: Coordinator) {
        coordinator.stop()
        coordinator.unhookPan()
    }

    final class Coordinator: NSObject {
        var command = 0
        var generation = 0
        private var link: CADisplayLink?
        private weak var anchor: UIView?

        func attach(_ view: UIView) {
            anchor = view
        }
        /// The offset we last accepted, so a system jump can be pulled back before it draws.
        private var applied: CGFloat?
        /// Who is writing `contentOffset` right now. KVO uses this as the log source.
        private var offsetSource = "swiftui"
        private var loggedOffset = CGFloat.nan
        var onIdle: (() -> Void)?
        var onCatchUp: (() -> Void)?
        var allowCatchUp = false
        var deadline: Date?
        private var observed: UIScrollView?
        private var observation: NSKeyValueObservation?
        private weak var hookedScroll: UIScrollView?
        /// This follow has seen the finger. A later coast is the flick, not the insert.
        private var sawFinger = false
        /// `onIdle` has already been told about this hold, so later touch moves do nothing.
        private var toldModel = false
        /// True only while this send's 6pt follow is stepping. User scrolling never sets it.
        private var following = false
        /// The short multi-row ease is running. A later command must not restart it as a 6pt creep.
        /// Media time of the first glide for this follow.
        private var sendClock: CFTimeInterval = 0
        /// The flight deadline this clock belongs to. A new send has a new deadline; the row-frame request does not.
        private var clockDeadline: Date?
        private var clamping = false
        /// The tap-time guess only seeds the deadline. The segment is rebuilt when the real gap is known.
        private var seeded = false
        private var peakCap: CGFloat = 48
        private var lastStamp: CFTimeInterval = 0
        private var velocity: CGFloat = 0
        private var landDeadline: CFTimeInterval = 0
        private var segmentFrom: CGFloat = 0
        private var segmentDistance: CGFloat = 0
        private var segmentTarget: CGFloat = 0
        private var segmentStart: CFTimeInterval = 0
        private var segmentDur: CFTimeInterval = 0.50
        private var segmentReady = false
        /// True when a smoothstep would peak above the cap, so the ease is the flatter distance-scaled shape.
        private var segmentFlat = false
        /// Speed at the start of this segment, in points per second. Zero starts a fresh ease.
        private var segmentV: CGFloat = 0
        /// Planned ramp, in frames. Used when the ease must stay under the cap and still end at rest.
        private var segmentUseRamp = false
        private var rampJerk: CGFloat = 12
        private var rampV0: CGFloat = 0
        private var rampPeak: CGFloat = 0
        private var rampUp: CGFloat = 0
        private var rampCruise: CGFloat = 0
        private var rampDown: CGFloat = 0
        /// Deep trips only. One entry per frame, summing to the segment distance.
        /// Empty for every other ease, which keeps the quadratic ramp.
        private var rampFrames: [CGFloat] = []
        /// How far the ease has actually played, in seconds of the plan.
        /// A callback adds the real elapsed time, so a 42ms tick covers ~2.5 frames.
        private var planClock: CFTimeInterval = 0
        /// Distance the previous nominal frame moved, so the next tick cannot accelerate
        /// faster than the smoothness limit.
        private var lastFrameStep: CGFloat = 0
        /// A visible row, so a content-size change above the viewport can be told apart
        /// from one below it.
        private var anchorID: UUID?
        private var anchorY: CGFloat = .nan
        /// Elapsed time of the last list tick. The projected landing uses this, not a guessed 60Hz.
        private var lastWall: CFTimeInterval = 0
        /// The coast-or-plan choice is made once, after row frames have had a tick to arrive.
        private var coastDecided = false
        private var waitedForSpots = false
        /// Long ticks skipped after the first post-insert tick. `<= 2` skips two and starts on the third.
        private var quietTicks = 0
        /// Media time of that first post-insert tick. The quiet bound is measured from here, not from the insert.
        private var quietBegan: CFTimeInterval = 0
        /// Last landing time published to the copy. A slip of one frame republishes it;
        /// the copy itself rebuilds at most once every two frames.
        private var publishedLanding: CFTimeInterval = 0
        private var lastLandingPublish: CFTimeInterval = 0
        /// The 12pt pull-back may happen once per displayed frame, not once per layout.
        private var pulledThisFrame = false
        /// Render-server scroll. The model stays put; the presentation layer moves during the insert layout.
        private var scrollCoasting = false
        private var coastFromY: CGFloat = 0
        private var coastToY: CGFloat = 0
        private var coastDur: CFTimeInterval = 0
        private var coastAt: CFTimeInterval = 0
        /// One coast per send. After handoff the per-frame ease owns the list.
        private var coastDone = false
        /// Deep plan built during the quiet wait. The first short tick writes the 12pt step.
        private var quietHolding = false
        /// Frames to keep pinning after a coast writes the model. Releasing on the
        /// handoff frame lets SwiftUI put the offset back and the rows jump.
        private var pinHold = 0
        /// Content height samples, so a long glide locks its aim only after estimates settle.
        private var settleHeight: CGFloat = .nan
        private var settleTicks = 0
        /// Last near-bottom coast step, so a remainder plan starts from that speed.
        private var coastLastStep: CGFloat = 12
        /// Steps of the coast on screen, so a mid-coast handoff keeps the current speed.
        private var coastSteps: [CGFloat] = []
        /// Gap was at most 144pt. The per-frame plan stays at or under 12pt.
        private var nearTrip = false
        /// Send whose glide is on screen now. 0 until its insert has returned.
        private var motionGeneration = 0
        /// Newest send that asked the list to move. It waits until its own insert returns.
        private var armedGeneration = 0

        /// Start the clock now. The scroll view may not be in the hierarchy yet; the tick retries.
        /// A newer send does not clear a glide that is already moving. That glide keeps
        /// its frames until the new insert returns, then the new trip starts from rest.
        func arm(fast: Bool) {
            _ = fast
            armedGeneration = generation
            sawFinger = false
            toldModel = false
            following = true
            if sendClock == 0 {
                sendClock = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : CACurrentMediaTime()
            }
            // A follow that is not waiting on an insert starts now. A deadline left
            // over from the previous send is already in the past; give it a fresh one.
            let pending = generation > 0
                && generation == SendFlightModel.currentGeneration
                && SendFlightModel.insertedGeneration < generation
                && motionGeneration < generation
            if !pending {
                let now = CACurrentMediaTime()
                if landDeadline < now + 1.0 / 60.0 {
                    landDeadline = now + 0.50
                    segmentReady = false
                }
            }
            if let scroll = anchor?.enclosingScrollView, applied == nil {
                applied = scroll.contentOffset.y
                loggedOffset = scroll.contentOffset.y
            }
            startLink()
            if allowCatchUp {
                let notify = onCatchUp
                DispatchQueue.main.async { notify?() }
            }
        }

        func stop() {
            link?.invalidate()
            link = nil
            following = false
            applied = nil
            unwatch()
        }

        /// Only while a 6pt send-follow is stepping, and never across a user touch.
        private func watch(_ scroll: UIScrollView) {
            guard observed !== scroll else { return }
            observation?.invalidate()
            observed = scroll
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                self?.noteOffset(on: scroll)
            }
        }

        private func unwatch() {
            observation?.invalidate()
            observation = nil
            observed = nil
        }

        func hookPan(from view: UIView) {
            guard let scroll = view.enclosingScrollView else { return }
            guard hookedScroll !== scroll else { return }
            unhookPan()
            scroll.panGestureRecognizer.addTarget(self, action: #selector(userPan(_:)))
            hookedScroll = scroll
        }

        func unhookPan() {
            hookedScroll?.panGestureRecognizer.removeTarget(self, action: #selector(userPan(_:)))
            hookedScroll = nil
        }

        /// Fires on the touch, before the next display tick can cancel the flick's velocity.
        @objc private func userPan(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began, .changed:
                sawFinger = true
                SendFlightModel.listFingerDown = true
                giveListToUser()
            case .ended, .cancelled, .failed:
                sawFinger = true
                SendFlightModel.listFingerDown = false
                giveListToUser()
            default:
                break
            }
        }

        private func fingerOn(_ scroll: UIScrollView) -> Bool {
            if scroll.isDragging || scroll.isTracking {
                sawFinger = true
                return true
            }
            switch scroll.panGestureRecognizer.state {
            case .began, .changed:
                sawFinger = true
                return true
            case .ended:
                return sawFinger
            default:
                break
            }
            // Coast after a real flick. An insert can set isDecelerating with no finger behind it.
            return sawFinger && scroll.isDecelerating
        }

        /// The drag owns the list from now on. Nothing may pull it back to the bottom.
        private func giveListToUser() {
            if !SendFlightModel.userHeldList {
                toldModel = false
                SendFlightModel.userHeldList = true
                SendFlightModel.reportScroll(0)
                link?.invalidate()
                link = nil
                following = false
                if let scroll = anchor?.enclosingScrollView, scrollCoasting {
                    let y = scroll.layer.presentation()?.bounds.origin.y ?? scroll.contentOffset.y
                    var bounds = scroll.bounds
                    bounds.origin.y = y
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    scroll.layer.bounds = bounds
                    scroll.layer.removeAnimation(forKey: "scrollCoast")
                    commitOffset(y, on: scroll, source: "user")
                    CATransaction.commit()
                    applied = y
                } else {
                    applied = nil
                }
                scrollCoasting = false
                coastDone = true
                velocity = 0
                segmentV = 0
            }
            // The touch can begin before the model callback is installed. Tell it once we have one.
            guard !toldModel else { return }
            let idle = onIdle
            guard let idle else { return }
            toldModel = true
            DispatchQueue.main.async { idle() }
        }

        /// Every contentOffset write, ours or SwiftUI's. `offsetSource` names the writer.
        private func noteOffset(on scroll: UIScrollView) {
            SendFlightModel.modelOffset = scroll.contentOffset.y
            let y = scroll.contentOffset.y
            let previous = loggedOffset
            if previous.isNaN || abs(y - previous) > 0.4 {
                SendMark.event(String(format: "scroll.offset %.1f -> %.1f %@", previous.isNaN ? y : previous, y, offsetSource))
                loggedOffset = y
            }
            guard offsetSource == "swiftui" else { return }
            capJump(on: scroll)
        }

        /// Put `y` on the scroll view and label the write so the observer does not pin it back.
        private func commitOffset(_ y: CGFloat, on scroll: UIScrollView, source: String) {
            offsetSource = source
            clamping = true
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
            clamping = false
            if abs(loggedOffset - y) > 0.4 || loggedOffset.isNaN {
                SendMark.event(String(format: "scroll.offset %.1f -> %.1f %@", loggedOffset.isNaN ? y : loggedOffset, y, source))
                loggedOffset = y
            }
            offsetSource = "swiftui"
            applied = y
            SendFlightModel.modelOffset = y
        }

        private var seenContentHeight = CGFloat.nan
        private var seenInsetTop = CGFloat.nan
        private var seenInsetBottom = CGFloat.nan

        /// Lowest and highest offsets that do not show blank space past the ends.
        private func validOffset(_ y: CGFloat, on scroll: UIScrollView) -> CGFloat {
            let inset = scroll.adjustedContentInset
            let minY = -inset.top
            let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
            return min(maxY, max(minY, y))
        }

        /// Content-size and inset changes. A large D1/deep offset jump that arrives with a
        /// content-size change is a LazyVStack estimate correction: keep the pixels put.
        /// Inset changes (keyboard, safe area) still follow SwiftUI. Returns true when handled.
        private func reconcileGeometry(on scroll: UIScrollView, proposed: CGFloat) -> Bool {
            let height = scroll.contentSize.height
            let top = scroll.adjustedContentInset.top
            let bottomInset = scroll.adjustedContentInset.bottom
            let dh = seenContentHeight.isNaN ? CGFloat(0) : height - seenContentHeight
            let dTop = seenInsetTop.isNaN ? CGFloat(0) : top - seenInsetTop
            let dBot = seenInsetBottom.isNaN ? CGFloat(0) : bottomInset - seenInsetBottom
            let changed = !seenContentHeight.isNaN && (
                abs(dh) > 0.5 || abs(dTop) > 0.5 || abs(dBot) > 0.5
            )
            seenContentHeight = height
            seenInsetTop = top
            seenInsetBottom = bottomInset
            guard changed else { return false }
            let base = applied ?? proposed
            let dy = proposed - base
            let insetChanged = abs(dTop) > 0.5 || abs(dBot) > 0.5
            // Rows re-measured above the viewport grow the content and leave the offset
            // alone, so the visible pixels jump. A view that was on screen moves by that
            // delta; shift the offset with it. Growth below the viewport does not move it.
            if !insetChanged, abs(dy) < 1.5, let shift = anchorShift(on: scroll), abs(shift) > 12, abs(dh) > 12 {
                let corrected = validOffset(base + shift, on: scroll)
                let who = anchorID?.uuidString ?? "-"
                SendMark.event(String(format: "geometry compensate above dh=%.1f shift=%.1f anchor=%@", dh, shift, who as NSString))
                if abs(scroll.contentOffset.y - corrected) > 0.5 {
                    commitOffset(corrected, on: scroll, source: "geometry")
                } else {
                    applied = corrected
                }
                return true
            }
            // Keyboard and safe-area insets still follow SwiftUI. A large offset jump
            // that arrives with a content-size change is a LazyVStack estimate.
            let longTrip = SendFlightModel.deepTrip || peakCap > 48 || abs(dy) > 100
            if longTrip, !insetChanged, abs(dy) > 48, abs(dh) > 48 {
                let keep = validOffset(base, on: scroll)
                SendMark.event(String(format: "geometry compensate dy=%.1f dh=%.1f", dy, dh))
                if abs(scroll.contentOffset.y - keep) > 0.5 {
                    commitOffset(keep, on: scroll, source: "geometry")
                } else {
                    applied = keep
                }
                return true
            }
            let y = validOffset(proposed, on: scroll)
            SendMark.event(String(format: "geometry dy=%.1f dh=%.1f", dy, dh))
            if abs(y - scroll.contentOffset.y) > 0.5 || abs(y - base) > 0.5 {
                commitOffset(y, on: scroll, source: "geometry")
            } else {
                applied = y
            }
            return true
        }

        private func capJump(on scroll: UIScrollView) {
            guard following, !clamping else { return }
            if fingerOn(scroll) {
                giveListToUser()
                DispatchQueue.main.async { [weak self] in self?.unwatch() }
                return
            }
            if scrollCoasting {
                if reconcileGeometry(on: scroll, proposed: scroll.contentOffset.y) { return }
                keepCoast(on: scroll)
                return
            }
            if reconcileGeometry(on: scroll, proposed: scroll.contentOffset.y) { return }
            let y = validOffset(scroll.contentOffset.y, on: scroll)
            guard let stored = applied else {
                applied = y
                return
            }
            let pinned = validOffset(stored, on: scroll)
            if abs(scroll.contentOffset.y - pinned) > 0.5 {
                commitOffset(pinned, on: scroll, source: "pin")
            }
        }

        /// Near-bottom only. The steps are the per-frame plan's own steps. A near trip
        /// holds to 0.44s when that is later, the same as the plan, and never adds frames.
        /// A landing past ~0.48s from the tap does not coast; the plan runs instead.
        /// The copy is given the same arrival.
        private func startCoast(on scroll: UIScrollView, from: CGFloat, distance: CGFloat) -> Bool {
            guard distance > 12, distance <= 144, !scrollCoasting else { return false }
            let now = CACurrentMediaTime()
            let base = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : now
            let steps = SendFlightPlan.steps(distance: distance, peak: 12)
            guard !steps.isEmpty else { return false }
            // The plan holds a near trip to 0.44s when that is later than the steps.
            // Stretching these same steps matches it. Extra ease frames are what ran long.
            let natural = CFTimeInterval(steps.count) / 60.0
            let untilFloor = (base + 0.44) - now
            let duration = max(natural, untilFloor)
            let projected = now + duration
            if projected - base > 0.48 {
                SendMark.event(String(format: "list.coast defer t=%.3f frames=%d", projected - base, steps.count))
                return false
            }
            installCoast(on: scroll, from: from, steps: steps, duration: duration)
            SendFlightModel.arriveAt = projected
            SendFlightModel.flightSpan = projected - base
            landDeadline = projected
            SendMark.event(String(format: "list.coast dist=%.0f frames=%d t=%.3f from=%.1f", distance, steps.count, projected - base, from))
            return true
        }

        /// A gap past one row whose rows SwiftUI has already built. D1 does not get
        /// here: the new row is not built, so coverage fails and the plan runs.
        /// Each keyframe is one legal displayed step. A trip under 700pt stretches to
        /// 0.46s from the tap when its steps finish sooner. A natural landing up to
        /// ~0.47s still coasts, at its own length. Later than that, the plan runs.
        private func startBuiltCoast(on scroll: UIScrollView, from: CGFloat, distance: CGFloat) -> Bool {
            guard distance > 12, distance <= 2000, !scrollCoasting, !SendFlightModel.deepTrip else { return false }
            let peak: CGFloat = distance > 700 ? 70 : min(peakCap, 48)
            let steps = SendFlightPlan.steps(distance: distance, peak: peak)
            guard steps.count >= 2 else { return false }
            let now = CACurrentMediaTime()
            let base = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : now
            let minDur = CFTimeInterval(steps.count) / 60.0
            let duration: CFTimeInterval
            if distance > 700 {
                let want = SendFlightModel.arriveAt - now
                duration = max(minDur, want > 0.05 ? want : minDur)
            } else if let aimed = SendFlightPlan.builtCoastDuration(minDur: minDur, untilAim: (base + 0.46) - now) {
                duration = aimed
            } else {
                SendMark.event(String(format: "list.coast built defer min=%.3f", minDur))
                return false
            }
            installCoast(on: scroll, from: from, steps: steps, duration: duration)
            let projected = now + duration
            SendFlightModel.arriveAt = projected
            SendFlightModel.flightSpan = projected - base
            landDeadline = projected
            SendMark.event(String(format: "list.coast built dist=%.0f frames=%d t=%.3f from=%.1f", distance, steps.count, projected - base, from))
            return true
        }

        private func installCoast(on scroll: UIScrollView, from: CGFloat, steps: [CGFloat], duration: CFTimeInterval? = nil) {
            guard !steps.isEmpty, !scrollCoasting else { return }
            coastLastStep = steps.last ?? 12
            coastSteps = steps
            var values: [CGPoint] = [CGPoint(x: scroll.bounds.origin.x, y: from)]
            var times: [NSNumber] = [0]
            var y = from
            for (index, step) in steps.enumerated() {
                y += step
                values.append(CGPoint(x: scroll.bounds.origin.x, y: y))
                times.append(NSNumber(value: Double(index + 1) / Double(steps.count)))
            }
            let anim = CAKeyframeAnimation(keyPath: "bounds.origin")
            anim.values = values.map { NSValue(cgPoint: $0) }
            anim.keyTimes = times
            anim.duration = duration ?? CFTimeInterval(steps.count) / 60.0
            anim.calculationMode = .linear
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            coastFromY = from
            coastToY = y
            coastDur = anim.duration
            coastAt = CACurrentMediaTime()
            scrollCoasting = true
            scroll.layer.add(anim, forKey: "scrollCoast")
        }

        /// The keyframe the coast is on right now, before stretch. A longer duration
        /// moves less per on-screen frame; the handoff scales this by that ratio.
        private func coastSpeedNow() -> CGFloat {
            guard !coastSteps.isEmpty else { return coastLastStep }
            let age = max(0, CACurrentMediaTime() - coastAt)
            let span = max(coastDur, 1.0 / 60.0)
            let index = min(coastSteps.count - 1, max(0, Int((age / span * Double(coastSteps.count)).rounded(.down))))
            return coastSteps[index]
        }

        /// Points per display frame actually on screen. `step` is the keyframe.
        private func coastShownSpeed() -> CGFloat {
            SendFlightPlan.coastHandoffStep(step: coastSpeedNow(), frames: coastSteps.count, duration: coastDur)
        }

        /// An outside offset change continues from the pixels on screen, not the coast start.
        /// The model is set to that pixel, and a restarted coast begins on the same pixel.
        private func keepCoast(on scroll: UIScrollView) {
            let model = scroll.contentOffset.y
            let shown = scroll.layer.presentation()?.bounds.origin.y ?? model
            if scroll.layer.animation(forKey: "scrollCoast") != nil,
               abs(model - coastFromY) <= 12 {
                return
            }
            let written = SendFlightPlan.handoffY(shown: shown)
            scrollCoasting = false
            writeOffset(written, on: scroll)
            let parked = scroll.contentOffset.y
            applied = parked
            let remain = coastToY - parked
            let speed = coastShownSpeed()
            SendMark.event(String(format: "list.handoff jump=%.2f shown=%.1f written=%.1f remain=%.1f v=%.0f", parked - shown, shown, parked, remain, speed * 60))
            guard remain > 12, remain <= 144 else {
                coastDone = true
                if remain > 144 {
                    velocity = speed * 60
                    quietTicks = 3
                }
                return
            }
            if !startCoast(on: scroll, from: parked, distance: remain) {
                coastDone = false
                quietTicks = 3
            }
        }

        /// Model offset becomes the on-screen position, then the coast animation comes off.
        private func writeOffset(_ y: CGFloat, on scroll: UIScrollView) {
            var bounds = scroll.bounds
            bounds.origin.y = y
            clamping = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scroll.layer.bounds = bounds
            scroll.layer.removeAnimation(forKey: "scrollCoast")
            commitOffset(y, on: scroll, source: "coast")
            CATransaction.commit()
            clamping = false
        }

        /// Presentation offset becomes the model, then the per-frame ease continues from there.
        private func endCoast(on scroll: UIScrollView) -> CGFloat {
            let shown = scroll.layer.presentation()?.bounds.origin.y ?? scroll.contentOffset.y
            let y = SendFlightPlan.handoffY(shown: shown)
            let elapsed = CACurrentMediaTime() - coastAt
            var bounds = scroll.bounds
            bounds.origin.y = y
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scroll.layer.bounds = bounds
            scroll.layer.removeAnimation(forKey: "scrollCoast")
            commitOffset(y, on: scroll, source: "list.handoff")
            CATransaction.commit()
            let written = scroll.contentOffset.y
            scrollCoasting = false
            coastDone = true
            pinHold = 4
            applied = written
            SendFlightModel.coastWritePending = true
            velocity = coastShownSpeed() * 60
            SendMark.event(String(format: "list.coast end y=%.1f", written))
            SendMark.event(String(format: "list.handoff jump=%.2f shown=%.1f written=%.1f age=%.3f v=%.0f", written - shown, shown, written, elapsed, velocity))
            return written
        }

        /// Layout can move the offset when a row is inserted. Put it back.
        /// The plan is the only writer while a send owns the list.
        private func holdJump(on scroll: UIScrollView, base: CGFloat) {
            if reconcileGeometry(on: scroll, proposed: scroll.contentOffset.y) { return }
            let pinned = validOffset(base, on: scroll)
            if abs(scroll.contentOffset.y - pinned) <= 0.5 {
                applied = pinned
                return
            }
            commitOffset(pinned, on: scroll, source: "layout")
        }

        /// Runs inside layout, before the frame is drawn. Only during a send's 6pt follow.
        func clampIfNeeded() {
            guard following, !clamping, let scroll = anchor?.enclosingScrollView else { return }
            if fingerOn(scroll) {
                giveListToUser()
                unwatch()
                return
            }
            if scrollCoasting {
                keepCoast(on: scroll)
                return
            }
            // The new gap is known here, often while the main thread is still inside
            // the insert layout. Report it so the copy can aim at the live row, but
            // do not start the scroll. A coast or a plan step begun here is already
            // moving when the layout stall freezes the run loop.
            let gap = bottom(scroll) - (applied ?? scroll.contentOffset.y)
            if SendFlightModel.insertedGeneration >= armedGeneration, armedGeneration > 0, gap >= 1.5 {
                SendFlightModel.reportScroll(gap)
            }
            holdJump(on: scroll, base: applied ?? scroll.contentOffset.y)
        }

        /// Take the newest send once its insert has returned. Until then the glide
        /// already running keeps its own frames. Deep and D1 start from rest here:
        /// a render-server coast would scroll through rows LazyVStack has not built.
        private func adoptNewSend() {
            guard armedGeneration > motionGeneration,
                  SendFlightModel.insertedGeneration >= armedGeneration else { return }
            var handoff: CGFloat = 0
            if scrollCoasting, let scroll = anchor?.enclosingScrollView {
                _ = endCoast(on: scroll)
                handoff = velocity
            }
            sendClock = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : CACurrentMediaTime()
            seeded = false
            segmentReady = false
            velocity = handoff
            coastDone = false
            scrollCoasting = false
            nearTrip = false
            planClock = 0
            lastFrameStep = handoff > 1 ? handoff / 60 : 0
            coastDecided = false
            waitedForSpots = false
            quietTicks = 0
            quietBegan = 0
            quietHolding = false
            pinHold = 0
            settleHeight = .nan
            settleTicks = 0
            lastContentH = .nan
            rowHeights.removeAll()
            publishedLanding = 0
            lastLandingPublish = 0
            motionGeneration = armedGeneration
        }

        private func startLink() {
            guard link == nil else { return }
            SendFlightPlan.checkOnce()
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFramesPerSecond = 60
            link.add(to: .main, forMode: .common)
            self.link = link
            SendMark.event("list.link")
        }

        /// Cap and copy bound from a distance. Called with the tap guess, then again with the real gap.
        private func classify(_ distance: CGFloat) {
            if distance > 2000 {
                peakCap = 110
                SendFlightModel.deepTrip = true
                SendFlightModel.copyLimit = 2.0
                SendFlightModel.flightSpan = 0.70
                if !SendFlightModel.longGlide {
                    SendFlightModel.longGlide = true
                    SendFlightModel.contentSettled = false
                }
            } else if distance > 700 {
                peakCap = max(peakCap, 70)
                if !SendFlightModel.longGlide {
                    SendFlightModel.longGlide = true
                    SendFlightModel.contentSettled = false
                }
            } else {
                peakCap = max(peakCap, 48)
            }
        }

        /// Rebuild the ease from the current offset toward `target`. Speed carries over
        /// because the new fraction starts at 0 only when we were already stopped;
        /// a moving list keeps its velocity by not jumping the position.
        private func beginSegment(toward target: CGFloat, from y: CGFloat, now: CFTimeInterval, dt: CFTimeInterval) {
            let distance = max(0, target - y)
            if distance > 2000 || SendFlightModel.deepTrip {
                classify(max(distance, 2001))
            } else {
                classify(distance)
            }
            var remain = max(1.0 / 60.0, landDeadline - now)
            let carried = velocity > 60 ? velocity : 0
            let perFrame = peakCap * 60
            let smoothNeed = Double(CGFloat(1.5) * distance / perFrame)
            let flatNeed = Double(distance / (CGFloat(0.88) * perFrame))
            let naturalPeak = remain > 0 ? CGFloat(1.5) * distance / CGFloat(remain) / 60 : peakCap
            segmentFlat = naturalPeak > peakCap && distance > 700
            let need = segmentFlat ? flatNeed : smoothNeed
            // A segment may run past half a second. Compressing it into the leftover
            // time is what pinned a 600pt insert at the cap and then dropped to 12pt.
            if need > remain {
                if SendFlightModel.deepTrip {
                    let limit = SendFlightModel.arriveAt
                    remain = min(need, max(remain, limit - now))
                } else if naturalPeak > peakCap {
                    // Compressing under the cap rides the ceiling and then stops dead.
                    remain = need
                } else if SendFlightModel.arriveAt > now + 1.0 / 60.0 {
                    remain = min(need, SendFlightModel.arriveAt - now)
                } else {
                    remain = need
                }
                landDeadline = now + remain
                let again = CGFloat(1.5) * distance / CGFloat(remain) / 60
                segmentFlat = again > peakCap && distance > 700
            }
            if nearTrip {
                // The fast 12pt ramp finishes before the 0.44s floor. Stretch it.
                // If the distance cannot fit by then, keep the longer honest time.
                let base = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : now
                let untilFloor = base + 0.44 - now
                let fastest = Double(distance / 12) / 60.0
                if untilFloor > fastest {
                    remain = max(remain, untilFloor)
                    landDeadline = now + remain
                }
            }
            let startFrames = min(peakCap, max(0, carried / 60))
            let uncapped = max(startFrames, naturalPeak)
            // A moving deep trip must not switch to the uncapped cubic. That cubic
            // asks for ~140pt a frame, the limiter cuts it to 110, and the list
            // then rides the cap and stops dead. Deep always stays on its frame plan,
            // including a short remainder, so the end can taper instead of dropping by 24.
            segmentUseRamp = segmentFlat || SendFlightModel.deepTrip || (carried > 60 && uncapped > peakCap)
            if segmentUseRamp {
                segmentDur = max(1.0 / 60.0, layoutRamp(distance: distance, v0: startFrames))
                if SendFlightModel.deepTrip {
                    // The recorded deadline stays at or before the tap's 1.0s cap.
                    // The ramp itself is not shortened; a deep coast started at the tap
                    // is what keeps those frames inside the cap.
                    let limit = SendFlightModel.arriveAt
                    let rampEnd = now + segmentDur
                    landDeadline = min(max(landDeadline, rampEnd), max(limit, now + 1.0 / 60.0))
                } else {
                    landDeadline = max(landDeadline, now + segmentDur)
                }
                segmentV = 0
            } else {
                segmentDur = max(1.0 / 60.0, remain)
                let span = CGFloat(segmentDur)
                segmentV = distance > 1 ? min(carried, 3 * distance / span) : 0
            }
            segmentFrom = y
            segmentDistance = distance
            segmentTarget = target
            // A re-plan on this frame would otherwise be evaluated at t = 0 and take no step.
            // Start one frame back so this frame continues at the speed we already have.
            // A deep trip also starts one frame back from rest: the first tick then takes the
            // 12pt opening step instead of a zero, which is the 0.03s the tapered stop needs.
            let deepPlan = SendFlightModel.deepTrip && segmentUseRamp
            segmentStart = (carried > 60 || deepPlan) ? now - max(dt, 1.0 / 60.0) : now
            segmentReady = true
            coastDecided = true
            velocity = carried
            planClock = 0
            if carried > 1 {
                lastFrameStep = min(nearTrip ? 12 : peakCap, carried / 60)
            }
            // Future ticks are the normal cadence. The post-insert stall is one long
            // sample and must not become the copy's budget.
            let steps = SendFlightPlan.steps(distance: distance, peak: nearTrip ? 12 : peakCap)
            var projected = now + Double(max(steps.count, 1)) / 60.0
            let base = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : now
            if nearTrip {
                let floorAt = base + 0.44
                if floorAt > projected { projected = floorAt }
            }
            publishLanding(projected, now: now, base: base, steps: steps.count)
        }

        /// Speed plan that never exceeds the cap and is at rest at both the planned end
        /// and, when it starts from a stop, the beginning. Frame-to-frame change is at
        /// most max(12, 25% of the peak). A deep trip uses the trapezoid from `deepFrames`.
        /// Returns the duration in seconds.
        private func layoutRamp(distance: CGFloat, v0: CGFloat) -> CFTimeInterval {
            rampFrames = []
            let cap = max(peakCap, 1)
            if SendFlightModel.deepTrip {
                rampFrames = deepFrames(distance: distance, v0: v0, cap: cap)
                let n = CGFloat(max(rampFrames.count, 1))
                rampJerk = 0
                rampV0 = min(max(0, v0), cap)
                rampPeak = cap
                rampUp = 0
                rampCruise = 0
                rampDown = n
                return Double(n) / 60.0
            }
            // From rest the first frame covers jerk/2. Keep that at or under 12,
            // and never change speed by more than a quarter of the peak.
            let jerk = min(24, max(12, cap * 0.25))
            let start = min(max(0, v0), cap)
            var peak = cap
            var nUp = max(0, (peak - start) / jerk)
            var nDown = peak / jerk
            var distUp = (start + peak) * 0.5 * nUp
            var distDown = peak * 0.5 * nDown
            if distance > 0, distUp + distDown > distance {
                let inside = jerk * distance + start * start * 0.5
                peak = min(cap, sqrt(max(start * start, inside)))
                if peak + 0.001 < start {
                    let j = max(jerk, start * start / (2 * max(distance, 0.001)))
                    rampJerk = j
                    rampV0 = start
                    rampPeak = start
                    rampUp = 0
                    rampCruise = 0
                    rampDown = start / j
                    return Double(rampDown) / 60.0
                }
                nUp = max(0, (peak - start) / jerk)
                nDown = peak / max(jerk, 0.001)
                distUp = (start + peak) * 0.5 * nUp
                distDown = peak * 0.5 * nDown
            }
            let nCruise = max(0, (distance - distUp - distDown) / max(peak, 0.001))
            rampJerk = jerk
            rampV0 = start
            rampPeak = peak
            rampUp = nUp
            rampCruise = nCruise
            rampDown = nDown
            return Double(nUp + nCruise + nDown) / 60.0
        }

        /// Deep trapezoid. From rest the climb is 12, 39, 66, 93, 110.
        /// Consecutive frames change by at most 27, one point inside the 27.5 cap.
        /// The stop is 83, 56, 32, 12. Cruise frames take whatever is left, at the cap.
        private func deepFrames(distance: CGFloat, v0: CGFloat, cap: CGFloat) -> [CGFloat] {
            let distance = max(0, distance)
            let limit = min(max(cap, 1), 110)
            guard distance > 0.05 else { return [] }
            let climb = deepClimb(from: v0, cap: limit)
            for count in stride(from: climb.count, through: 1, by: -1) {
                let rise = Array(climb.prefix(count))
                guard let last = rise.last else { continue }
                let fall = deepFall(from: last)
                let extra = distance - rise.reduce(0, +) - fall.reduce(0, +)
                if extra < -0.05 { continue }
                if let frames = deepJoin(rise: rise, extra: extra, fall: fall, cap: limit, distance: distance),
                   deepPlanFits(frames, distance: distance, v0: v0, strictStart: true) {
                    return frames
                }
            }
            return deepShorter(distance: distance, v0: v0, cap: limit)
        }

        /// Climb toward the cap. From rest each step rises by 27pt: 12, 39, 66, 93, 110.
        private func deepClimb(from v0: CGFloat, cap: CGFloat) -> [CGFloat] {
            let top = min(110, cap)
            if v0 < 1 { return [12, 39, 66, 93, top] }
            var speed = min(max(v0, 0), cap)
            var steps = [speed]
            while speed + 0.5 < top {
                let next = min(top, speed + 27)
                if next > cap || next <= speed + 0.05 { break }
                steps.append(next)
                speed = next
            }
            return steps
        }

        /// Slowdown from a cruise at the cap: 83, 56, 32, 12. Each drop is at most 27,
        /// and no step above 12pt is taken with 42pt or less left.
        private func deepFall(from entry: CGFloat) -> [CGFloat] {
            if entry >= 100 - 0.05 {
                return [83, 56, 32, 12]
            }
            if entry >= 84 - 0.05, entry - 84 <= 27 + 0.05 {
                return [83, 56, 32, 12]
            }
            var steps: [CGFloat] = []
            var speed = entry
            while speed > 57.5 {
                let next = speed - 27
                if next < 30 { break }
                steps.append(next)
                speed = next
            }
            if speed > 30.1, speed - 30 <= 27.5 + 0.05 {
                steps.append(30)
                speed = 30
            }
            if speed + 0.05 >= 12, speed - 12 <= 27.5 + 0.05 {
                steps.append(contentsOf: [12, 6])
            } else if speed < 12 {
                if speed > 6.05 { steps.append(min(6, speed)) }
            } else {
                steps.append(speed - 27)
                steps.append(contentsOf: [12, 6])
            }
            return steps
        }

        /// How many equal cruise frames keep each one inside the cap and within 27
        /// of both the climb and the slowdown. Nil when no such count exists.
        private func deepCruiseCount(extra: CGFloat, before: CGFloat, after: CGFloat, cap: CGFloat) -> Int? {
            if extra <= 0.05 {
                return abs(before - after) <= 27 + 0.05 ? 0 : nil
            }
            let low = max(0, before - 27, after - 27)
            let high = min(cap, before + 27, after + 27)
            if high < low - 0.01 { return nil }
            let least = max(1, Int((extra / high - 1e-9).rounded(.up)))
            if low < 0.5 { return least }
            let most = Int((extra / low + 1e-9).rounded(.down))
            if least > most { return nil }
            return least
        }

        private func deepJoin(
            rise: [CGFloat], extra: CGFloat, fall: [CGFloat], cap: CGFloat, distance: CGFloat
        ) -> [CGFloat]? {
            guard let after = fall.first, let before = rise.last else { return nil }
            guard let count = deepCruiseCount(extra: max(extra, 0), before: before, after: after, cap: cap) else {
                return nil
            }
            var frames = rise
            if count > 0 {
                let each = extra / CGFloat(count)
                frames.append(contentsOf: Array(repeating: each, count: count))
            }
            frames.append(contentsOf: fall)
            let error = distance - frames.reduce(0, +)
            if count > 0 {
                let index = rise.count + count - 1
                frames[index] += error
                if frames[index] > cap + 0.02 || frames[index] < -0.02 { return nil }
            } else if let last = frames.indices.last {
                frames[last] += error
            }
            return frames
        }

        /// A distance too short for the full climb. Starts as close to the current
        /// speed as the stop allows, and still ends 12, 6.
        private func deepShorter(distance: CGFloat, v0: CGFloat, cap: CGFloat) -> [CGFloat] {
            let ladder = v0 < 1 ? [12.0, 39, 66, 93, min(110, cap)] : deepClimb(from: v0, cap: cap)
            var options: [[CGFloat]] = []
            for count in 1...ladder.count {
                options.append(Array(ladder.prefix(count)))
            }
            if v0 >= 1 {
                var speed = min(v0, cap)
                let floor = max(0, v0 - 27.5)
                while speed >= floor - 0.1 {
                    options.append([speed])
                    speed -= 1
                }
            }
            var bestScore = -Double.greatestFiniteMagnitude
            var best: [CGFloat] = []
            let wanted = v0 >= 1 ? v0 : 12
            for rise in options {
                guard let last = rise.last else { continue }
                let fall = deepFall(from: last)
                let extra = distance - rise.reduce(0, +) - fall.reduce(0, +)
                if extra < -0.05 { continue }
                guard let frames = deepJoin(rise: rise, extra: extra, fall: fall, cap: cap, distance: distance),
                      deepPlanFits(frames, distance: distance, v0: v0, strictStart: false) else { continue }
                let score = Double(rise.count) * 1000 - Double(abs(wanted - rise[0]))
                if score > bestScore {
                    bestScore = score
                    best = frames
                }
            }
            if !best.isEmpty { return best }
            return deepSmallSteps(distance)
        }

        /// Last resort when the remaining distance cannot decelerate from the current speed.
        /// Every step stays at or under 12, so the end clamp has nothing to correct.
        private func deepSmallSteps(_ distance: CGFloat) -> [CGFloat] {
            if distance <= 6 { return [distance] }
            if distance <= 18 {
                let lead = min(12, distance - 6)
                return [lead, distance - lead]
            }
            var frames: [CGFloat] = []
            var left = distance
            while left > 18.05 {
                let take = min(12, left - 18)
                frames.append(take)
                left -= take
            }
            let middle = min(12, max(0, left - 6))
            frames.append(middle)
            frames.append(6)
            if let last = frames.indices.last {
                frames[last] += distance - frames.reduce(0, +)
            }
            return frames
        }

        private func deepPlanFits(_ frames: [CGFloat], distance: CGFloat, v0: CGFloat, strictStart: Bool) -> Bool {
            guard !frames.isEmpty else { return distance <= 0.05 }
            if abs(frames.reduce(0, +) - distance) > 0.03 { return false }
            for index in frames.indices {
                let step = frames[index]
                if step < -0.02 || step > 110.03 { return false }
                let gap = frames[index...].reduce(0, +)
                if step > 12.01, gap <= 42.05 { return false }
                if index > 0, abs(step - frames[index - 1]) > 27.58 { return false }
            }
            if strictStart, v0 >= 1, let first = frames.first {
                if first - v0 > 0.08 || v0 - first > 27.58 { return false }
                let peak = frames.indices.max { frames[$0] < frames[$1] } ?? 0
                if peak > 0 {
                    for index in 1...peak where frames[index] - frames[index - 1] > 27.58 {
                        return false
                    }
                }
            }
            return true
        }

        private func rampDistance(through f: CGFloat) -> CGFloat {
            if !rampFrames.isEmpty {
                if f <= 0 { return 0 }
                var total: CGFloat = 0
                var left = f
                for step in rampFrames {
                    if left >= 1 {
                        total += step
                        left -= 1
                    } else {
                        return total + step * max(0, left)
                    }
                }
                return total
            }
            let up = rampV0 * rampUp + rampJerk * rampUp * rampUp * 0.5
            if f <= rampUp {
                return rampV0 * f + rampJerk * f * f * 0.5
            }
            if f <= rampUp + rampCruise {
                return up + rampPeak * (f - rampUp)
            }
            let d = min(rampDown, f - rampUp - rampCruise)
            return up + rampPeak * rampCruise + rampPeak * d - rampJerk * d * d * 0.5
        }

        /// Fraction of the segment distance covered at `t` in 0...1. Ends at 1 with speed 0.
        private func covered(_ t: CGFloat) -> CGFloat {
            let x = min(1, max(0, t))
            if segmentUseRamp {
                let total = rampUp + rampCruise + rampDown
                if total < 0.001 || segmentDistance < 1 { return 1 }
                let f = min(total, x * total)
                return min(1, max(0, rampDistance(through: f) / segmentDistance))
            }
            if segmentV > 1, segmentDistance > 1 {
                let T = CGFloat(segmentDur)
                let D = segmentDistance
                let vT = segmentV * T
                let pos = vT * x + (3 * D - 2 * vT) * x * x + (vT - 2 * D) * x * x * x
                return min(1, max(0, pos / D))
            }
            if !segmentFlat {
                return x * x * (3 - 2 * x)
            }
            let e: CGFloat = 0.12
            let whole = 1 - e
            if x < e {
                let u = x / e
                let ramp = u * u * u - 0.5 * u * u * u * u
                return (e * ramp) / whole
            }
            if x <= 1 - e {
                return (x - 0.5 * e) / whole
            }
            let u = (x - (1 - e)) / e
            let tail = u - u * u * u + 0.5 * u * u * u * u
            let before = 0.5 * e + (1 - 2 * e)
            return (before + e * tail) / whole
        }

        /// One displayed step. Elapsed time is used only while the curve stays inside
        /// a single frame: first and last at most 12, change at most max(12, 25% of the
        /// peak), and the peak itself (12 near, 70 on D1, 110 deep).
        private func planStep(over wall: CFTimeInterval, gap: CGFloat) -> CGFloat {
            let frame = 1.0 / 60.0
            guard gap > 0.5, segmentDur > 0 else { return 0 }
            let opening = planClock < frame * 0.5 && lastFrameStep < 1
            var spend = opening ? frame : min(max(wall, 0), 0.05)
            let start = planClock
            func take(_ seconds: CFTimeInterval) -> CGFloat {
                let end = min(segmentDur, start + seconds)
                let t0 = min(1, start / segmentDur)
                let t1 = min(1, end / segmentDur)
                return segmentDistance * max(0, covered(t1) - covered(t0))
            }
            var raw = take(spend)
            var step = displayedCap(raw, gap: gap)
            if !opening, raw > step + 0.4, spend > frame + 0.0001 {
                spend = frame
                raw = take(spend)
                step = displayedCap(raw, gap: gap)
            }
            planClock = min(segmentDur, start + spend)
            step = min(max(0, step), gap)
            lastFrameStep = step
            return step
        }

        /// The most this callback may move, given the step that was just displayed.
        private func displayedCap(_ proposed: CGFloat, gap: CGFloat) -> CGFloat {
            SendFlightPlan.capDisplay(
                proposed: proposed,
                previous: lastFrameStep,
                gap: gap,
                peak: nearTrip ? min(peakCap, 12) : peakCap
            )
        }

        /// Push the published landing when the list is more than one frame behind it.
        /// The copy rebuilds on its own two-frame limit, so this does not restart every tick.
        private func publishLanding(_ projected: CFTimeInterval, now: CFTimeInterval, base: CFTimeInterval, steps: Int) {
            publishedLanding = projected
            lastLandingPublish = now
            SendFlightModel.arriveAt = projected
            SendFlightModel.flightSpan = projected - base
            landDeadline = projected
            if SendFlightModel.deepTrip || !nearTrip {
                SendMark.event(String(format: "list.landing t=%.3f steps=%d cadence=17ms", projected - base, steps))
            }
        }

        private func noteSlip(now: CFTimeInterval) {
            guard segmentReady, publishedLanding > 0 else { return }
            let behind = (now - segmentStart) - planClock
            guard behind > 1.0 / 60.0, now - lastLandingPublish >= 2.0 / 60.0 else { return }
            let revised = now + max(0, segmentDur - planClock)
            guard revised > publishedLanding + 1.0 / 60.0 else { return }
            let base = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : now
            publishLanding(revised, now: now, base: base, steps: Int((segmentDur - planClock) * 60))
            SendMark.event(String(format: "list.landing slip behind=%.0fms", behind * 1000))
        }

        /// Continuous built coverage from the current offset through the final viewport.
        /// One row overlapping the destination is not enough.
        private func rowsCover(on scroll: UIScrollView, from start: CGFloat, through target: CGFloat) -> Bool {
            let end = target + max(scroll.bounds.height, 1)
            let hit = SendFlightPlan.covers(
                SendFlightModel.rowSpots,
                from: start,
                through: end,
                lastID: SendFlightModel.lastRowID
            )
            SendMark.event("list.cover ok=\(hit ? 1 : 0) rows=\(SendFlightModel.rowSpots.count)")
            return hit
        }

        /// How far the anchored row's content-space top moved. Content added above the
        /// viewport moves that top. Content added below it does not.
        private func anchorShift(on scroll: UIScrollView) -> CGFloat? {
            let top = scroll.contentOffset.y
            let viewH = scroll.bounds.height
            let visible = SendFlightModel.rowSpots.filter { spot in
                spot.minY < top + viewH && spot.minY + spot.height > top
            }
            guard let spot = visible.min(by: {
                abs($0.minY - top) < abs($1.minY - top)
            }) else { return nil }
            let shift: CGFloat?
            if anchorID == spot.id, !anchorY.isNaN {
                shift = spot.minY - anchorY
                if let shift, abs(shift) > 12 {
                    SendMark.event(String(format: "list.anchor shift=%.1f id=%@", shift, spot.id.uuidString as NSString))
                }
            } else {
                shift = nil
                SendMark.event("anchor id=\(spot.id.uuidString)")
            }
            anchorID = spot.id
            anchorY = spot.minY
            return shift
        }

        /// Content height during a send. A smooth decay here is an implicit animation.
        private var lastContentH: CGFloat = .nan
        private var rowHeights: [UUID: CGFloat] = [:]

        private func noteContent(_ height: CGFloat) {
            let dh = lastContentH.isNaN ? CGFloat(0) : height - lastContentH
            if !lastContentH.isNaN, abs(dh) > 0.4, SendFlightModel.currentGeneration > 0 {
                let who = biggestRowChange()
                SendMark.event(String(format: "list.height dh=%.1f h=%.1f %@", dh, height, who as NSString))
            }
            lastContentH = height
            for spot in SendFlightModel.rowSpots {
                rowHeights[spot.id] = spot.height
            }
            guard SendFlightModel.longGlide else { return }
            // Height is still until the glide reaches the bottom marker. Counting
            // those ticks would freeze the aim on the estimate, before the shrink.
            guard SendFlightModel.bottomSeenThisSend else {
                settleTicks = 0
                SendFlightModel.contentSettled = false
                return
            }
            if settleHeight.isNaN || abs(height - settleHeight) > 1 {
                settleHeight = height
                settleTicks = 0
                SendFlightModel.contentSettled = false
                SendFlightModel.lockedFinalOffset = .nan
                SendFlightModel.lockedContentTop = .nan
            } else {
                settleTicks += 1
                if settleTicks >= 2 { SendFlightModel.contentSettled = true }
            }
        }

        private var loggedTrack: CGFloat = .nan

        /// The row whose height moved the most since the previous sample.
        private func biggestRowChange() -> String {
            var bestID = "layout"
            var best: CGFloat = 0
            for spot in SendFlightModel.rowSpots {
                guard let prev = rowHeights[spot.id] else { continue }
                let delta = spot.height - prev
                if abs(delta) > abs(best) {
                    best = delta
                    bestID = String(spot.id.uuidString.prefix(8))
                }
            }
            if abs(best) < 0.4 { return "layout" }
            return String(format: "row %@ %+.1f", bestID, best)
        }

        /// Where the list should stop. On a long glide, after the aim is locked, a
        /// content-top change moves this end so the user row stays on that aim.
        /// Bottom sends keep the content bottom, so a streaming reply can still grow.
        private func planTarget(on scroll: UIScrollView) -> CGFloat {
            let end = bottom(scroll)
            guard SendFlightModel.longGlide else { return end }
            let tracked = SendFlightPlan.alignedOffset(
                frozenFinal: SendFlightModel.lockedFinalOffset,
                contentThen: SendFlightModel.lockedContentTop,
                contentNow: SendFlightModel.userContentTop() ?? .nan,
                limit: end
            )
            if abs(tracked - end) > 1, loggedTrack.isNaN || abs(tracked - loggedTrack) > 1 {
                loggedTrack = tracked
                SendMark.event(String(format: "list.aimtrack end=%.1f bottom=%.1f", tracked, end))
            }
            return tracked
        }

        private func bottom(_ scroll: UIScrollView) -> CGFloat {
            let inset = scroll.adjustedContentInset
            return max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
        }

        @objc private func tick(_ link: CADisplayLink) {
            // Not in the hierarchy yet. Keep the clock; stopping here is why the list
            // waited until the row's frame, about 0.3s after the tap.
            guard let scroll = anchor?.enclosingScrollView else { return }
            if observed == nil {
                following = true
                watch(scroll)
            }
            if fingerOn(scroll) {
                giveListToUser()
                unwatch()
                return
            }
            let now = link.targetTimestamp
            if sendClock == 0 { sendClock = now }
            let wall = lastStamp > 0 ? now - lastStamp : link.duration
            let dt = min(1.0 / 60.0, max(link.duration, 1.0 / 120.0))
            lastWall = wall
            lastStamp = now
            pulledThisFrame = false
            SendMark.Signpost.endAfterInsert()
            adoptNewSend()
            // Hold only while this send's insert has not returned. finish() bumps
            // pop.generation without an insert; the send number is currentGeneration.
            // A streaming follow or any other non-send scroll runs immediately.
            let sendPending = armedGeneration == SendFlightModel.currentGeneration
                && SendFlightModel.insertedGeneration < armedGeneration
                && motionGeneration < armedGeneration
            if sendPending {
                let modelY = applied ?? scroll.contentOffset.y
                let gap = bottom(scroll) - modelY
                if gap > 144 {
                    // The distance is known. The list stays at rest until this insert's
                    // stall is over, then starts from rest. A coast here parks mid-motion.
                    classify(gap)
                    SendFlightModel.noteTrip(gap)
                    SendFlightModel.reportScroll(gap)
                }
                if wall > 0.02 || (sendClock > 0 && now - sendClock < 0.40) {
                    SendMark.event(String(format: "list.tick hold dt=%.0fms", wall * 1000))
                }
                return
            }
            if scrollCoasting {
                let age = CACurrentMediaTime() - coastAt
                let modelY = applied ?? scroll.contentOffset.y
                let modelGap = bottom(scroll) - modelY
                // Model gap only. The presentation offset moves every frame; mixing it
                // with the row's model minY slides the copy's slot.
                SendFlightModel.reportScroll(modelGap)
                let inserted = SendFlightModel.insertedGeneration >= armedGeneration && armedGeneration > 0
                if inserted, coastToY > bottom(scroll) + 48 {
                    _ = endCoast(on: scroll)
                } else if age < coastDur - (1.0 / 120.0) {
                    if age < 0.40 {
                        SendMark.event(String(format: "list.coasting dt=%.0fms age=%.3f", wall * 1000, age))
                    }
                    return
                } else {
                    _ = endCoast(on: scroll)
                }
            }
            noteContent(scroll.contentSize.height)
            let live = planTarget(on: scroll)
            let y = applied ?? scroll.contentOffset.y
            let gap = live - y
            if !seeded {
                seeded = true
                let distance = max(0, gap)
                nearTrip = distance <= 144 && !SendFlightModel.deepTrip
                classify(distance)
                let sendGlide = SendFlightModel.currentGeneration > 0
                    && armedGeneration == SendFlightModel.currentGeneration
                    && SendFlightModel.insertedGeneration >= armedGeneration
                if sendGlide {
                    SendFlightModel.noteTrip(distance)
                    // From the tap, not from this tick. A 0.50s ease that starts when the
                    // block ends is what parked B and C2 past half a second.
                    landDeadline = SendFlightModel.arriveAt
                } else if landDeadline < now + 1.0 / 60.0 {
                    landDeadline = now + 0.50
                }
            }
            // A coast only while SwiftUI has already built every row the trip will cross.
            // Deep writes the real offset. D1 does not coast: the new row is not built,
            // coverage fails, and the per-frame plan drives the offset.
            if !coastDecided, !scrollCoasting, !coastDone, !SendFlightModel.deepTrip, gap > 12, gap <= 2000,
               SendFlightModel.rowSpots.isEmpty, !waitedForSpots {
                waitedForSpots = true
                SendMark.event("list.cover ok=0 rows=0")
                return
            }
            if !coastDecided, !scrollCoasting, !coastDone, !SendFlightModel.deepTrip, gap > 12, gap <= 2000,
               rowsCover(on: scroll, from: y, through: y + gap) {
                if gap <= 144, gap <= scroll.bounds.height {
                    nearTrip = true
                    if startCoast(on: scroll, from: y, distance: gap) {
                        coastDecided = true
                        SendFlightModel.reportScroll(gap)
                        SendMark.event(String(format: "list.tick dt=%.0fms step=coast gap=%.0f", wall * 1000, gap))
                        return
                    }
                    coastDecided = true
                } else if gap > 144 {
                    if startBuiltCoast(on: scroll, from: y, distance: gap) {
                        coastDecided = true
                        SendFlightModel.reportScroll(gap)
                        return
                    }
                    coastDecided = true
                }
            }
            // The tick after the insert is long, and the one after that often is too.
            // A 12pt step on that tick is a park. Wait for a tick under 25ms, then start from rest.
            // A refused coast waits the same way. It does not start on the stall tick.
            let afterInsert = SendFlightModel.currentGeneration > 0
                && armedGeneration == SendFlightModel.currentGeneration
                && SendFlightModel.insertedGeneration >= armedGeneration
            if (!segmentReady || quietHolding), !scrollCoasting, wall >= 0.025, afterInsert {
                if quietBegan == 0 { quietBegan = now }
                quietTicks += 1
                let sinceFirst = now - quietBegan
                // Skip while this tick is long, at most two have been skipped, and
                // less than 150ms has passed since the first post-insert tick.
                if quietTicks <= 2, sinceFirst < 0.150 {
                    // Build the deep plan on the long tick. Write nothing until a short
                    // tick, and do not count the wait as frames of the glide.
                    if SendFlightModel.deepTrip, !segmentReady {
                        beginSegment(toward: live, from: y, now: now, dt: dt)
                        planClock = 0
                        lastFrameStep = 0
                        quietHolding = true
                        // Drop the per-row probes on this already-long tick.
                        SendFlightModel.dropRowProbes()
                    }
                    SendFlightModel.reportScroll(gap)
                    SendMark.event(String(format: "list.tick quiet dt=%.0fms n=%d", wall * 1000, quietTicks))
                    return
                }
            }
            if quietHolding {
                quietHolding = false
                planClock = 0
                lastFrameStep = 0
                let frames = max(rampFrames.count, 1)
                segmentStart = now - (1.0 / 60.0)
                segmentDur = Double(frames) / 60.0
                let base = SendFlightModel.tapTime > 0 ? SendFlightModel.tapTime : now
                publishLanding(now + Double(frames) / 60.0, now: now, base: base, steps: frames)
            }
            if SendFlightModel.deepTrip, segmentReady {
                SendFlightModel.dropRowProbes()
            }
            // Far from the end, a deep plan ignores a small shift of the target.
            // Near the end, or once the plan has finished with distance left, it
            // retargets so the stop stays inside the last-step and change caps.
            let peak = max(peakCap, 12)
            let endCloser = segmentReady && live + 1 < segmentTarget
            let nearEnd = gap < peak * 2 || endCloser
            let planDone = segmentReady && planClock >= segmentDur - 0.000_1
            let farDeep = SendFlightModel.deepTrip && !nearEnd && !planDone
            let slack: CGFloat = farDeep ? peak : 12
            if gap > 1.5, !segmentReady || abs(live - segmentTarget) > slack || planDone {
                beginSegment(toward: live, from: y, now: now, dt: dt)
            }
            var step: CGFloat = 0
            if segmentReady, gap > 0.5 {
                // One displayed frame. Extra elapsed time is not spent past the cap.
                step = planStep(over: wall, gap: gap)
            }
            if wall > 0.02 || abs(step) > 0.2 || (sendClock > 0 && now - sendClock < 1.2) {
                SendMark.event(String(format: "list.tick dt=%.0fms step=%.0f gap=%.0f y=%.1f", wall * 1000, step, gap, y))
            }
            if step > 0.2 {
                velocity = step * 60
                commitOffset(y + step, on: scroll, source: "plan")
            } else if applied == nil {
                applied = y
                velocity = 0
            }
            SendFlightModel.reportScroll(live - (applied ?? y))
            noteSlip(now: now)
            _ = anchorShift(on: scroll)
            let parked = live - (applied ?? y) < 1.5
            let done = segmentReady && now >= segmentStart + segmentDur + 0.08
            if parked {
                velocity = 0
                segmentV = 0
            }
            if parked, pinHold > 0 {
                pinHold -= 1
            } else if parked, done || (coastDone && !segmentReady) {
                following = false
                applied = nil
                unwatch()
                link.invalidate()
                self.link = nil
                SendFlightModel.reportScroll(0)
                DispatchQueue.main.async { [onIdle] in onIdle?() }
            }
        }
    }
}

/// Reports layout so a jump in content offset can be pulled back before the frame draws.
final class ClampHost: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        SendMark.Signpost.beginScrollLayout()
        super.layoutSubviews()
        onLayout?()
        SendMark.Signpost.endScrollLayout()
    }
}

/// Window-level copy for the first send only, before a transcript exists.
/// A Core Animation leg keeps it moving while the main thread is busy. Once the
/// row is on screen, a display link follows that live frame until the two meet.
final class FlightHost: NSObject {
    static let shared = FlightHost()
    var onLanded: ((Int) -> Void)?
    var scrollSettled: () -> Bool = { true }

    private var bubble: UIView?
    private var generation = 0
    private var link: CADisplayLink?
    private var liveRow: CGRect = .zero
    private var rowTicks = 0
    private var start = CGPoint.zero
    private var guess = CGPoint.zero
    private var startedAt = Date()
    private var landed = false
    /// The row has been told to appear. The copy stays until it has been opaque for two ticks.
    private var revealAsked = false
    private var rowOpaque = false
    private var opaqueTicks = 0
    private var revealAt = Date()
    /// The remainder is one render-server keyframe. A main-thread stall cannot park it.
    private var correcting = false
    private var correctTarget = CGPoint.zero
    var onReleased: ((Int) -> Void)?

    func begin(text: String, field: CGRect, transcript: CGRect, generation: Int) {
        guard field.width > 1, let host = Self.overlay else {
            SendFlightTrace.log("begin skipped field=\(field) no window")
            return
        }
        // Same bubble, same window, for the whole flight. Never tear it down mid-way.
        if bubble == nil || self.generation != generation {
            bubble?.layer.removeAllAnimations()
            bubble?.removeFromSuperview()
            let view = Self.bubble(text)
            view.isUserInteractionEnabled = false
            let canvas = host.rootViewController?.view ?? host
            canvas.addSubview(view)
            bubble = view
            SendFlightTrace.log("added gen=\(generation) host=\(host.frame)")
        }
        self.generation = generation
        startedAt = Date()
        landed = false
        liveRow = .zero
        rowTicks = 0
        revealAsked = false
        rowOpaque = false
        opaqueTicks = 0
        correcting = false
        correctTarget = .zero
        guard let view = bubble else { return }
        start = CGPoint(x: field.minX + view.bounds.width / 2, y: field.minY + view.bounds.height / 2)
        // First row: top of the transcript area, trailing edge, size from the text.
        if transcript.width > 1, transcript.minY + 8 < field.minY {
            guess = CGPoint(
                x: transcript.maxX - 16 - view.bounds.width / 2,
                y: transcript.minY + 12 + view.bounds.height / 2
            )
        } else {
            guess = CGPoint(x: field.maxX - view.bounds.width / 2, y: start.y - 160)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer.removeAllAnimations()
        view.layer.position = start
        CATransaction.commit()
        let anim = CABasicAnimation(keyPath: "position")
        anim.fromValue = start
        anim.toValue = guess
        anim.duration = 0.42
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        view.layer.add(anim, forKey: "flight")
        CATransaction.flush()
        SendMark.Signpost.caCommit()
        SendFlightModel.coastFlushed = true
        SendFlightTrace.log("phase=diagonal from=\(start) to=\(guess)")
        startLink()
    }

    func noteRow(_ frame: CGRect) {
        guard frame.width > 1 else { return }
        if liveRow == .zero { rowTicks = 0 }
        liveRow = frame
        SendFlightTrace.log("row frame \(frame)")
    }

    /// The real row is about to be shown. Keep this copy until it has painted.
    func holdForRow(generation: Int) {
        guard generation == self.generation, bubble != nil else { return }
        if !revealAsked { revealAt = Date() }
        revealAsked = true
        startLink()
    }

    /// The row's opacity is 1. Two later display ticks may then drop the copy.
    func noteRowOpaque() {
        guard !rowOpaque else { return }
        rowOpaque = true
        opaqueTicks = 0
        SendFlightTrace.log("row opacity seen, hold copy")
    }

    func remove(generation: Int) {
        guard generation == self.generation else { return }
        guard bubble != nil || link != nil else { return }
        SendFlightTrace.log("removed gen=\(generation)")
        link?.invalidate()
        link = nil
        bubble?.layer.removeAllAnimations()
        bubble?.removeFromSuperview()
        bubble = nil
        liveRow = .zero
        rowTicks = 0
        revealAsked = false
        rowOpaque = false
        opaqueTicks = 0
        correcting = false
        correctTarget = .zero
    }

    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        guard let view = bubble, !landed else { return }
        if revealAsked {
            // The row is shown. Stay on screen until its opacity-1 report, then two more ticks.
            guard rowOpaque else {
                if Date().timeIntervalSince(revealAt) > 0.4 {
                    SendFlightTrace.log("overlap timeout")
                    finishOverlap()
                }
                return
            }
            opaqueTicks += 1
            SendFlightTrace.log("overlap tick \(opaqueTicks)")
            if opaqueTicks >= 2 {
                finishOverlap()
            }
            return
        }
        // Until the row exists, leave the Core Animation leg alone so it keeps
        // gliding even while the main thread is inside the first save.
        // Let the diagonal finish. The remainder is one keyframe, not a 6pt crawl.
        guard liveRow.width > 1 else { return }
        rowTicks += 1
        guard rowTicks >= 2 else {
            SendFlightTrace.log("row frame seen, wait one tick")
            return
        }
        // The model layer stays at the start until handoff. Only the presentation
        // position is where the copy is actually drawn; falling back to the model
        // and then removing the animation is the hundreds-of-points jump.
        guard let current = view.layer.presentation()?.position else { return }
        let target = CGPoint(x: liveRow.midX, y: liveRow.midY)
        let gap = hypot(target.x - current.x, target.y - current.y)
        let age = Date().timeIntervalSince(startedAt)
        let settled = scrollSettled()
        SendFlightTrace.log(String(
            format: "window pres=%.1f,%.1f row=%.1f,%.1f gap=%.1f age=%.2f settled=%@ ticks=%d",
            current.x, current.y, target.x, target.y, gap, age, settled ? "1" : "0", rowTicks
        ))
        let xOK = abs(current.x - target.x) <= 2
        let yOK = abs(current.y - target.y) <= 2
        guard settled else {
            SendFlightTrace.log("handoff wait scroll")
            SendMark.event(String(format: "copy.land refuse row=1 clear=1 gap=%.1f atSlot=%d x=%d frozen=0", gap, yOK ? 1 : 0, xOK ? 1 : 0))
            return
        }
        if gap < 1.5 || (correcting && xOK && yOK) {
            // Already on the row, or the keyframe has reached it. Hand it off.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.layer.position = current
            view.layer.removeAllAnimations()
            view.layer.position = target
            CATransaction.commit()
            SendFlightTrace.log("handoff window gap=\(gap) hold")
            revealAsked = true
            revealAt = Date()
            onLanded?(generation)
            return
        }
        // The diagonal owns the opening. Once it has finished, the rest is one
        // keyframe on the render server, so the reply-row stall cannot park it.
        guard age >= 0.42 else {
            SendMark.event(String(format: "copy.land refuse row=1 clear=1 gap=%.1f atSlot=%d x=%d frozen=0", gap, yOK ? 1 : 0, xOK ? 1 : 0))
            return
        }
        if !correcting || hypot(target.x - correctTarget.x, target.y - correctTarget.y) > 2 {
            installCorrection(on: view, to: target)
        }
        SendMark.event(String(format: "copy.land refuse row=1 clear=1 gap=%.1f atSlot=%d x=%d frozen=%d", gap, yOK ? 1 : 0, xOK ? 1 : 0, correcting ? 1 : 0))
    }

    /// Remainder of the new-chat flight, from the presentation position to the row.
    private func installCorrection(on view: UIView, to target: CGPoint) {
        guard let current = view.layer.presentation()?.position else { return }
        let span = hypot(target.x - current.x, target.y - current.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer.position = current
        view.layer.removeAnimation(forKey: "flight")
        view.layer.removeAnimation(forKey: "correct")
        CATransaction.commit()
        correcting = true
        correctTarget = target
        guard span > 1.5 else { return }
        let ux = (target.x - current.x) / span
        let uy = (target.y - current.y) / span
        let frames = max(4, Int(ceil(span / 24.0)))
        let steps = pacedTravel(span, frames: frames, cap: 24, opening: 12)
        var dist: CGFloat = 0
        var values: [CGPoint] = [current]
        for step in steps {
            dist = min(span, dist + step)
            values.append(CGPoint(x: current.x + ux * dist, y: current.y + uy * dist))
            if dist >= span - 0.5 { break }
        }
        if let last = values.last, hypot(last.x - target.x, last.y - target.y) > 0.5 {
            values.append(target)
        }
        let slots = max(values.count - 1, 1)
        let anim = CAKeyframeAnimation(keyPath: "position")
        anim.values = values.map { NSValue(cgPoint: $0) }
        anim.keyTimes = (0...slots).map { NSNumber(value: Double($0) / Double(slots)) }
        anim.duration = CFTimeInterval(slots) / 60.0
        anim.calculationMode = .linear
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer.add(anim, forKey: "correct")
        CATransaction.commit()
        SendMark.event(String(format: "copy.slot %.0f,%.0f -> %.0f,%.0f frames=%d", current.x, current.y, target.x, target.y, slots))
    }

    /// Drop the copy only after the opaque row has had two display ticks on top of it.
    private func finishOverlap() {
        guard !landed else { return }
        landed = true
        let gen = generation
        SendFlightTrace.log("removed gen=\(gen) after overlap")
        link?.invalidate()
        link = nil
        bubble?.layer.removeAllAnimations()
        bubble?.removeFromSuperview()
        bubble = nil
        liveRow = .zero
        rowTicks = 0
        revealAsked = false
        rowOpaque = false
        opaqueTicks = 0
        correcting = false
        correctTarget = .zero
        onReleased?(gen)
    }

    private static func bubble(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = UIColor(Theme.textPrimary)
        label.numberOfLines = 0
        let maxWidth: CGFloat = 260
        let textSize = label.sizeThatFits(CGSize(width: maxWidth - 36, height: 2000))
        label.frame = CGRect(x: 18, y: 14, width: ceil(textSize.width), height: ceil(textSize.height))
        let box = UIView(frame: CGRect(x: 0, y: 0, width: label.frame.width + 36, height: label.frame.height + 28))
        box.backgroundColor = UIColor(Theme.userBubble)
        box.layer.cornerRadius = 22
        box.layer.borderWidth = 1.3
        box.layer.borderColor = UIColor(Theme.accent).withAlphaComponent(0.85).cgColor
        box.addSubview(label)
        return box
    }

    /// One overlay window for the life of the process. The welcome-to-chat swap
    /// cannot remove it, and it never takes taps.
    private static var overlayWindow: UIWindow?
    private static var overlay: UIWindow? {
        if let overlayWindow { return overlayWindow }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }
        let window = PassThroughWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = .statusBar + 1
        window.backgroundColor = .clear
        window.isHidden = false
        let root = UIViewController()
        root.view.backgroundColor = .clear
        root.view.isUserInteractionEnabled = false
        window.rootViewController = root
        overlayWindow = window
        SendFlightTrace.log("overlay window created \(window.frame)")
        return window
    }
}

/// One displayed frame of a scroll plan. Pure, so the sum, the caps, a replan,
/// and the cadence projection can be checked without a device.
enum SendFlightPlan {
    static func steps(distance: CGFloat, peak: CGFloat) -> [CGFloat] {
        let delta = max(CGFloat(12), peak * 0.25)
        let built = base(distance: max(0, distance), peak: peak, delta: delta)
        return absorb(built, remainder: distance - built.reduce(0, +), delta: delta, peak: peak)
    }

    /// Normal cadence. A stall sample is not an input.
    static func project(stepCount: Int, now: CFTimeInterval) -> CFTimeInterval {
        now + CFTimeInterval(max(stepCount, 1)) / 60.0
    }

    /// Length of a built coast. `untilAim` is the time left until 0.46s from the tap.
    /// Stretch to that aim when the steps finish sooner. A natural landing up to ~0.47s
    /// still coasts, at its own length. Later than that, the plan runs.
    static func builtCoastDuration(minDur: CFTimeInterval, untilAim: CFTimeInterval) -> CFTimeInterval? {
        let slack: CFTimeInterval = 0.01
        guard minDur > 0, minDur <= untilAim + slack + 0.000_1 else { return nil }
        if untilAim + 0.000_1 >= minDur, untilAim > 1.0 / 120.0 {
            return max(minDur, untilAim)
        }
        return minDur
    }

    /// The offset a coast handoff writes. It is the position already on screen.
    static func handoffY(shown: CGFloat) -> CGFloat { shown }

    /// Flight-space row top. `raw` was measured at `geometryOffset`.
    /// Later offset writes shift it. A content-top callback is not applied:
    /// the frame and the content top are not one sample, and adding both counts the move twice.
    static func revealedY(raw: CGFloat, modelOffset: CGFloat, geometryOffset: CGFloat) -> CGFloat {
        guard geometryOffset.isFinite, modelOffset.isFinite else { return raw }
        return raw - (modelOffset - geometryOffset)
    }

    /// End offset that keeps the user row on the aim locked at `frozenFinal`.
    /// A content-top change is absorbed here. The result never passes the content bottom.
    static func alignedOffset(frozenFinal: CGFloat, contentThen: CGFloat, contentNow: CGFloat, limit: CGFloat) -> CGFloat {
        guard frozenFinal.isFinite, contentThen.isFinite, contentNow.isFinite else { return limit }
        let wanted = frozenFinal + (contentNow - contentThen)
        if wanted > limit { return limit }
        return wanted
    }

    /// Landing y from the row's current top and the list gap.
    /// When the gap has already been reported closed but the row top has not moved,
    /// the frame is still the pre-scroll one. Keep the prediction from the last moving sample.
    static func slotY(rowY: CGFloat, remain: CGFloat, anchoredRow: CGFloat, anchoredRemain: CGFloat) -> (y: CGFloat, stale: Bool) {
        if abs(remain) >= 1.5 {
            return (rowY - remain, false)
        }
        if anchoredRemain > 12, anchoredRow.isFinite, abs(rowY - anchoredRow) < anchoredRemain - 12 {
            return (anchoredRow - anchoredRemain, true)
        }
        return (rowY, false)
    }

    /// On-screen step of a coast keyframe. A stretched coast plays the same steps
    /// over a longer duration, so the handoff is `step * (frames / 60) / duration`.
    static func coastHandoffStep(step: CGFloat, frames: Int, duration: CFTimeInterval) -> CGFloat {
        let natural = Double(max(frames, 1)) / 60.0
        let span = max(duration, 1.0 / 60.0)
        return max(0, step) * CGFloat(natural / span)
    }

    /// The cap `planStep` applies to one displayed change.
    static func capDisplay(proposed: CGFloat, previous: CGFloat, gap: CGFloat, peak: CGFloat) -> CGFloat {
        let maxDelta = max(CGFloat(12), peak * 0.25)
        let hi: CGFloat
        let lo: CGFloat
        if previous < 1 {
            hi = min(peak, 12)
            lo = 0
        } else {
            hi = min(peak, previous + maxDelta)
            lo = max(0, previous - maxDelta)
        }
        if gap <= 12, gap + 0.05 >= lo, gap <= hi + 0.05 {
            return gap
        }
        var step = min(max(proposed, lo), hi, gap)
        if step >= gap - 0.05, gap > 12 {
            let slowed = min(hi, max(lo, previous < 1 ? 12 : previous - maxDelta))
            if slowed < gap { step = slowed }
        }
        return max(0, step)
    }

    static func covers(
        _ spots: [RowContentSpot],
        from start: CGFloat,
        through end: CGFloat,
        lastID: UUID? = nil
    ) -> Bool {
        coveredEnd(spots, from: start, through: end, lastID: lastID) >= end - 4
    }

    /// Walks row frames in the scroll content's coordinate space (the padded stack).
    /// Once the chain reaches the last probed row, the spacer and the inset below it
    /// are covered too. An empty placeholder that was not probed does not count.
    static func coveredEnd(
        _ spots: [RowContentSpot],
        from start: CGFloat,
        through end: CGFloat = .greatestFiniteMagnitude,
        lastID: UUID? = nil
    ) -> CGFloat {
        let allowance = RowContentSpace.spacing + RowContentSpace.spacingSlack
        var cursor = start
        for spot in spots.sorted(by: { $0.minY < $1.minY }) {
            let maxY = spot.minY + max(spot.height, 1)
            if maxY < cursor - 2 { continue }
            if spot.minY > cursor + allowance { break }
            cursor = max(cursor, maxY)
            if let lastID, spot.id == lastID {
                cursor = max(cursor, end)
            }
        }
        return cursor
    }

    static func checkOnce() {
        if checked { return }
        checked = true
        checkSums()
        checkCurve()
        checkCadence()
        checkCoverage()
        checkCoast()
        SendMark.event("plan.check ok")
    }

    private static var checked = false

    private static func checkSums() {
        let cases: [(String, CGFloat, CGFloat)] = [
            ("B", 157, 48), ("RH", 400, 48), ("D1", 1490, 70), ("D1b", 1465, 70),
            ("deep", 4185, 110), ("deep2", 3327, 110), ("near", 108, 12)
        ]
        for item in cases {
            let plan = steps(distance: item.1, peak: item.2)
            let sum = plan.reduce(0, +)
            expect(abs(sum - item.1) < 0.05, "\(item.0) sum \(sum)")
            expect(plan.first ?? 99 <= 12.05, "\(item.0) first")
            expect(plan.last ?? 99 <= 12.05, "\(item.0) last")
            let delta = max(CGFloat(12), item.2 * 0.25)
            for step in plan {
                expect(step <= item.2 + 0.05, "\(item.0) peak")
            }
            for index in plan.indices.dropFirst() {
                expect(abs(plan[index] - plan[index - 1]) <= delta + 0.05, "\(item.0) delta")
            }
        }
    }

    private static func checkCurve() {
        let cases: [(String, CGFloat, CGFloat)] = [
            ("D1", 1490, 70), ("deep", 4185, 110), ("near", 108, 12)
        ]
        for item in cases {
            let plan = steps(distance: item.1, peak: item.2)
            var previous: CGFloat = 0
            var left = item.1
            for expected in plan {
                let got = capDisplay(proposed: expected, previous: previous, gap: left, peak: item.2)
                expect(abs(got - expected) < 0.05, "curve \(item.0) step \(got) != \(expected)")
                left -= got
                previous = got
            }
            expect(abs(left) < 0.05, "curve \(item.0) left \(left)")
        }
        let kept = capDisplay(proposed: 0, previous: 70, gap: 400, peak: 70)
        expect(kept > 50 && kept <= 70, "curve replan 70 -> \(kept)")
        let deepKept = capDisplay(proposed: 0, previous: 110, gap: 800, peak: 110)
        expect(deepKept > 80 && deepKept <= 110, "curve replan 110 -> \(deepKept)")
        let opening = capDisplay(proposed: 90, previous: 0, gap: 200, peak: 70)
        expect(opening <= 12.05, "curve opening \(opening)")
    }

    private static func checkCadence() {
        let landing = project(stepCount: 25, now: 0.156)
        expect(abs(landing - (0.156 + 25.0 / 60.0)) < 0.001, "cadence")
        expect(landing < 0.156 + 25.0 * 0.05, "not stall budget")
    }

    private static func checkCoverage() {
        let hole = [RowContentSpot(id: UUID(), minY: 1400, height: 40)]
        expect(!covers(hole, from: 0, through: 1600), "one row is not a path")
        var chain: [RowContentSpot] = []
        var y: CGFloat = 0
        while y < 1600 {
            chain.append(RowContentSpot(id: UUID(), minY: y, height: 40))
            y += 40
        }
        expect(covers(chain, from: 0, through: 1600), "continuous path")
        var spaced: [RowContentSpot] = []
        var top: CGFloat = 0
        while top < 800 {
            spaced.append(RowContentSpot(id: UUID(), minY: top, height: 40))
            top += 40 + RowContentSpace.spacing
        }
        let spacedEnd = (spaced.last?.minY ?? 0) + 40
        expect(covers(spaced, from: 0, through: spacedEnd), "22pt gaps")
        if spaced.count >= 2 {
            let hole = spaced
            var broken = hole
            broken.remove(at: broken.count / 2)
            expect(!covers(broken, from: 0, through: spacedEnd), "a missing row is a hole")
        }
        // Probe space starts at the stack. Scroll content adds 12pt of top padding,
        // a 1pt bottom spacer, and a 34pt inset. The last message closes that tail.
        let pad: CGFloat = 12
        let spacer: CGFloat = 1
        let inset: CGFloat = 34
        var laid: [RowContentSpot] = []
        var probeY: CGFloat = 0
        for index in 0..<5 {
            let id = UUID()
            laid.append(RowContentSpot(id: id, minY: probeY, height: 40))
            probeY += 40
            if index < 4 { probeY += RowContentSpace.spacing }
        }
        probeY += spacer
        let contentEnd = pad + probeY + inset
        let last = laid[laid.count - 1].id
        expect(covers(laid, from: 0, through: contentEnd, lastID: last), "padding and inset after the last probed row")
        let placeholder = UUID()
        expect(!covers(laid, from: 0, through: contentEnd, lastID: placeholder), "a 0pt unprobed placeholder is not the tail")
        var shifted = laid.map { RowContentSpot(id: $0.id, minY: $0.minY + pad, height: $0.height) }
        expect(covers(shifted, from: 0, through: contentEnd, lastID: last), "rows already in content space")
        shifted.remove(at: 2)
        expect(!covers(shifted, from: 0, through: contentEnd, lastID: last), "a gap still wins over the tail")
    }

    private static func checkCoast() {
        let near = steps(distance: 120, peak: 12)
        expect(near.count == 10, "near 120pt is 10 frames, got \(near.count)")
        expect((near.first ?? 99) <= 12.05 && (near.last ?? 99) <= 12.05, "near caps")
        let late = 0.311 + Double(near.count) / 60.0
        expect(late > 0.47 && late <= 0.48, "late near coast runs under 0.48")
        let early = 0.250 + Double(near.count) / 60.0
        expect(early <= 0.48, "early near coast may run")
        let stretched = builtCoastDuration(minDur: 0.20, untilAim: 0.26)
        expect(abs((stretched ?? -1) - 0.26) < 0.000_1, "built coast stretches to 0.46")
        let kept = builtCoastDuration(minDur: 0.102, untilAim: 0.10)
        expect(abs((kept ?? -1) - 0.102) < 0.000_1, "built coast accepts a 0.462 landing")
        expect(builtCoastDuration(minDur: 0.30, untilAim: 0.10) == nil, "built coast does not pass 0.47")
        expect(builtCoastDuration(minDur: 0.12, untilAim: 0.10) == nil, "built coast refuses past 0.47")
        let exact = builtCoastDuration(minDur: 0.46, untilAim: 0.46)
        expect(abs((exact ?? -1) - 0.46) < 0.000_1, "built coast keeps its min duration at 0.46")
        expect(handoffY(shown: 320) == 320, "handoff writes the pixels")
        let stretchedDur = (16.0 / 60.0) * (48.0 / 30.0)
        let shownStep = coastHandoffStep(step: 48, frames: 16, duration: stretchedDur)
        expect(abs(shownStep - 30) < 0.05, "stretched coast hands off ~30pt not 48")
        let plainStep = coastHandoffStep(step: 48, frames: 16, duration: 16.0 / 60.0)
        expect(abs(plainStep - 48) < 0.05, "unstretched coast hands off the keyframe")
        let moving = slotY(rowY: 600, remain: 411, anchoredRow: .nan, anchoredRemain: 0)
        expect(abs(moving.y - 189) < 0.05 && !moving.stale, "slot while the list is moving")
        let stale = slotY(rowY: 600, remain: 0, anchoredRow: 600, anchoredRemain: 411)
        expect(stale.stale && abs(stale.y - 189) < 0.05, "closed gap keeps the pre-scroll prediction")
        let arrived = slotY(rowY: 189, remain: 0, anchoredRow: 600, anchoredRemain: 411)
        expect(!arrived.stale && abs(arrived.y - 189) < 0.05, "row frame that caught up is the slot")
        let written = revealedY(raw: 606.4, modelOffset: 411, geometryOffset: 0)
        expect(abs(written - 195.4) < 0.05, "stale probe reveals from the written offset")
        // Content callback first: the flight frame is still the old one. Do not shift it.
        expect(abs(revealedY(raw: 513.8, modelOffset: 100, geometryOffset: 100) - 513.8) < 0.05, "content callback does not move the frame")
        // Shifted frame first, then the content callback. The frame already includes the shrink.
        var frameFirst = 423.8
        let afterFrame = revealedY(raw: frameFirst, modelOffset: 100, geometryOffset: 100)
        frameFirst = afterFrame
        expect(abs(revealedY(raw: frameFirst, modelOffset: 100, geometryOffset: 100) - 423.8) < 0.05, "content callback after the frame is not a second shift")
        // Frame measured before a 70pt write, then the write, then the frame catches up.
        expect(abs(revealedY(raw: 500, modelOffset: 170, geometryOffset: 100) - 430) < 0.05, "write before the frame shifts the reveal")
        expect(abs(revealedY(raw: 430, modelOffset: 170, geometryOffset: 170) - 430) < 0.05, "frame after the write is not shifted again")
        let held = alignedOffset(frozenFinal: 4500, contentThen: 5000, contentNow: 4900, limit: 4400)
        expect(abs(held - 4400) < 0.05, "shrink stays inside the content bottom")
        let tracked = alignedOffset(frozenFinal: 4500, contentThen: 5000, contentNow: 4900, limit: 4600)
        expect(abs(tracked - 4400) < 0.05, "content-top shrink shortens the end offset")
    }

    private static func expect(_ ok: Bool, _ name: String) {
        if ok { return }
        SendMark.event("plan.check FAIL \(name)")
        assertionFailure("SendFlight plan \(name)")
    }

    private static func brake(from speed: CGFloat, delta: CGFloat) -> [CGFloat] {
        var steps: [CGFloat] = []
        var speed = speed
        while speed > 12.05, steps.count < 20 {
            let next = max(CGFloat(12), speed - delta)
            if next >= speed - 0.01 { break }
            steps.append(next)
            speed = next
        }
        return steps
    }

    private static func base(distance: CGFloat, peak: CGFloat, delta: CGFloat) -> [CGFloat] {
        if distance <= 12.05 { return [distance] }
        var climb: [CGFloat] = [min(12, peak, distance)]
        while let last = climb.last, last + 0.5 < peak {
            let next = min(peak, last + delta)
            let grown = climb.reduce(0, +) + next + brake(from: next, delta: delta).reduce(0, +)
            if grown > distance + 0.05 { break }
            climb.append(next)
        }
        var speed = climb[climb.count - 1]
        var tail = brake(from: speed, delta: delta)
        while climb.reduce(0, +) + tail.reduce(0, +) > distance + 0.05, climb.count > 1 {
            climb.removeLast()
            speed = climb[climb.count - 1]
            tail = brake(from: speed, delta: delta)
        }
        var steps = climb
        var left = distance - climb.reduce(0, +) - tail.reduce(0, +)
        if speed > 0, left > 0.05 {
            let count = Int((left / speed).rounded(.down))
            if count > 0 {
                steps.append(contentsOf: Array(repeating: speed, count: count))
                left -= CGFloat(count) * speed
            }
        }
        steps.append(contentsOf: tail)
        return steps
    }

    private static func roomUp(_ steps: [CGFloat], index: Int, delta: CGFloat, peak: CGFloat) -> CGFloat {
        let previous = index == 0 ? CGFloat(12) : steps[index - 1] + delta
        var cap = min(peak, previous)
        if index == 0 || index == steps.count - 1 { cap = min(cap, 12) }
        if index + 1 < steps.count { cap = min(cap, steps[index + 1] + delta) }
        return max(0, cap - steps[index])
    }

    private static func roomDown(_ steps: [CGFloat], index: Int, delta: CGFloat) -> CGFloat {
        var floor = CGFloat(0)
        if index > 0 { floor = max(floor, steps[index - 1] - delta) }
        if index + 1 < steps.count { floor = max(floor, steps[index + 1] - delta) }
        return max(0, steps[index] - floor)
    }

    private static func absorb(_ steps: [CGFloat], remainder: CGFloat, delta: CGFloat, peak: CGFloat) -> [CGFloat] {
        var steps = steps
        var left = remainder
        var guardCount = 0
        while left > 0.02, guardCount < 30, !steps.isEmpty {
            guardCount += 1
            var moved = false
            for index in steps.indices {
                let add = min(roomUp(steps, index: index, delta: delta, peak: peak), left)
                if add > 0.01 {
                    steps[index] += add
                    left -= add
                    moved = true
                }
                if left <= 0.02 { break }
            }
            if left <= 0.02 || !moved {
                if left <= 0.02 { break }
                var insert = steps.count - 1
                while insert > 0, steps[insert] < steps[insert - 1] - 0.1 { insert -= 1 }
                let frame = min(peak, steps[insert] + delta)
                steps.insert(frame, at: insert + 1)
                left -= frame
                if left < -0.02 {
                    var need = -left
                    for index in stride(from: steps.count - 1, through: 0, by: -1) {
                        let shed = min(roomDown(steps, index: index, delta: delta), need)
                        if shed > 0.01 {
                            steps[index] -= shed
                            need -= shed
                        }
                        if need <= 0.02 { break }
                    }
                    left = -need
                }
            }
        }
        return steps
    }
}

/// Lets taps fall through to the app. The flying copy must not swallow Send.
final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }
}
