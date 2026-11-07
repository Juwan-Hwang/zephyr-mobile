// 实时活动 + 灵动岛。数据：ZephyrActivityAttributes（App 的 LiveActivityController 负责 request/update/end）。

import ActivityKit
import SwiftUI
import WidgetKit
import ZephyrDesign

struct ZephyrLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ZephyrActivityAttributes.self) { context in
            LiveActivityLockView(state: context.state, accent: WidgetStyle.accent(context.attributes.accent),
                                 isStale: context.isStale)
                .activityBackgroundTint(ZTokens.Colors.screenGlass)
                .activitySystemActionForegroundColor(ZTokens.Colors.screenT1)
                .widgetURL(WidgetLinks.home)
        } dynamicIsland: { context in
            let accent = WidgetStyle.accent(context.attributes.accent)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: ZTokens.Space.n2) {
                        IslandCompactLeading(accent: accent)
                        Text("Zephyr").zType(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ConnectionTimer(since: context.state.connectedSince)
                        .zType(.headline, monospacedDigits: true)
                        .fontDesign(.monospaced)
                        .foregroundStyle(ZTokens.Colors.screenT2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                IslandCompactLeading(accent: accent)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state, isStale: context.isStale)
            } minimal: {
                IslandMinimal(accent: accent)
            }
            .widgetURL(WidgetLinks.home)
            .keylineTint(accent)
        }
    }
}

#Preview("锁屏", as: .content, using: ZephyrActivityAttributes(startedAt: .now, accent: "blue")) {
    ZephyrLiveActivity()
} contentStates: {
    ZephyrActivityAttributes.ContentState.prototype()
}

#Preview("灵动岛", as: .dynamicIsland(.compact), using: ZephyrActivityAttributes(startedAt: .now, accent: "blue")) {
    ZephyrLiveActivity()
} contentStates: {
    ZephyrActivityAttributes.ContentState.prototype()
}
