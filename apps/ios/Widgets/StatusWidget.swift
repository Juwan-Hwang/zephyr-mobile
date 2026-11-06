// 主屏小组件「Zephyr」：小号 = 速率 + 模式 + 电源；中号 = 速率 + 今日用量。

import SwiftUI
import WidgetKit

struct StatusWidget: Widget {
    static let kind = WidgetKinds.status

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SharedTimelineProvider()) { entry in
            StatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Zephyr")
        .description("连接状态、实时速率与今日用量，一键连接或断开。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatusWidgetEntryView: View {
    var entry: SharedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetContainer {
            switch family {
            case .systemMedium: StatusMediumView(state: entry.state, now: entry.date)
            default: StatusSmallView(state: entry.state)
            }
        }
        .widgetURL(WidgetLinks.home)
    }
}

#Preview(as: .systemSmall) {
    StatusWidget()
} timeline: {
    SharedEntry(date: .now, state: .prototype())
    SharedEntry(date: .now, state: .empty)
}

#Preview(as: .systemMedium) {
    StatusWidget()
} timeline: {
    SharedEntry(date: .now, state: .prototype())
}
