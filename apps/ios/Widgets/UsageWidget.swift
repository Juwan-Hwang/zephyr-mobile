// 主屏小组件「今日」：今日用量 + 24 小时柱状图。

import SwiftUI
import WidgetKit

struct UsageWidget: Widget {
    static let kind = WidgetKinds.usage

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SharedTimelineProvider()) { entry in
            WidgetContainer {
                UsageSmallView(state: entry.state, now: entry.date)
            }
            .widgetURL(WidgetLinks.today)
        }
        .configurationDisplayName("今日")
        .description("今天用了多少流量，按小时分布。")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    UsageWidget()
} timeline: {
    SharedEntry(date: .now, state: .prototype())
}
