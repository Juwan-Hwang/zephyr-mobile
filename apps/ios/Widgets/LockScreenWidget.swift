// 锁屏小组件：圆形速率环 / 矩形场景摘要 / 单行速率。

import SwiftUI
import WidgetKit

struct LockScreenWidget: Widget {
    static let kind = WidgetKinds.lockScreen

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SharedTimelineProvider()) { entry in
            LockScreenEntryView(entry: entry)
        }
        .configurationDisplayName("Zephyr")
        .description("在锁屏上查看速率与场景。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenEntryView: View {
    var entry: SharedEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: LockCircularView(state: entry.state)
            case .accessoryRectangular: LockRectangularView(state: entry.state)
            default: LockInlineView(state: entry.state)
            }
        }
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
        .widgetURL(WidgetLinks.home)
    }
}

#Preview(as: .accessoryCircular) {
    LockScreenWidget()
} timeline: {
    SharedEntry(date: .now, state: .prototype())
}

#Preview(as: .accessoryRectangular) {
    LockScreenWidget()
} timeline: {
    SharedEntry(date: .now, state: .prototype())
}
