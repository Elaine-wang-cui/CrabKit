import ActivityKit
import Foundation

/// 管灵动岛里那只：开始干活时开一个实时活动，每秒推一次帧号让它动起来，干完换开心再收起。
/// 要用灵动岛，app 的 Info.plist 里要有 NSSupportsLiveActivities = YES，
/// 还要一个小组件扩展，里面放 CrabKitWidgets 的 CrabLiveActivity()。
@MainActor
public final class IslandCrab {
    public static let shared = IslandCrab()

    private var activity: Activity<CrabActivityAttributes>?
    private var ticker: Task<Void, Never>?
    private var phase: CrabActivityAttributes.Phase = .thinking
    private var frame = 0

    public init() {}

    public func start(title: String = "", style: CrabStyle) {
        cancel()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        phase = .thinking
        frame = 0
        let state = CrabActivityAttributes.ContentState(phase: phase, frame: frame)
        activity = try? Activity.request(
            attributes: CrabActivityAttributes(title: title, style: style),
            content: .init(state: state, staleDate: nil),
            pushType: nil
        )
        guard activity != nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    public func set(_ newPhase: CrabActivityAttributes.Phase) {
        guard activity != nil, newPhase != phase else { return }
        phase = newPhase
        push()
    }

    /// 干完了：换开心帧，几秒后自己收起
    public func finish() {
        ticker?.cancel()
        ticker = nil
        guard let activity else { return }
        self.activity = nil
        let state = CrabActivityAttributes.ContentState(phase: .done, frame: 0)
        Task {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(4)))
        }
    }

    /// 出错或者被停：马上收起
    public func cancel() {
        ticker?.cancel()
        ticker = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func tick() {
        frame += 1
        push()
    }

    private func push() {
        guard let activity else { return }
        let state = CrabActivityAttributes.ContentState(phase: phase, frame: frame)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }
}
