import ActivityKit
import CrabKit
import SwiftUI
import WidgetKit

/// 灵动岛和锁屏上的小螃蟹。放进你的小组件扩展的 WidgetBundle 里。
public struct CrabLiveActivity: Widget {
    public init() {}

    private let accent = Color(red: 0.914, green: 0.439, blue: 0.310)

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CrabActivityAttributes.self) { context in
            // 锁屏和没有灵动岛的机型
            HStack(spacing: 14) {
                PixelCrab(frame: context.state.crabFrame(context.attributes.style), pixel: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.phase.label)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.12, green: 0.11, blue: 0.10))
                    if !context.attributes.title.isEmpty {
                        Text(context.attributes.title)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.52, green: 0.49, blue: 0.45))
                    }
                }
                Spacer()
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.976, green: 0.973, blue: 0.965))
            .activitySystemActionForegroundColor(.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PixelCrab(frame: context.state.crabFrame(context.attributes.style), pixel: 2)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase.label)
                        .font(.headline)
                        .foregroundStyle(accent)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                PixelCrab(frame: context.state.crabFrame(context.attributes.style), pixel: 0.95)
            } compactTrailing: {
                Text(context.state.phase.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(accent)
            } minimal: {
                PixelCrab(frame: context.state.crabFrame(context.attributes.style), pixel: 0.78)
            }
            .keylineTint(accent)
        }
    }
}
