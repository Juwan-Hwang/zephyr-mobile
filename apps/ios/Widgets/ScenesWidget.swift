// 主屏小组件「场景」：AI / 视频 / 其他 当前出口与延迟，点按某行打开对应场景。

import SwiftUI
import WidgetKit

struct ScenesWidget: Widget {
    static let kind = WidgetKinds.scenes

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SharedTimelineProvider()) { entry in
            WidgetContainer {
                ScenesMediumView(state: entry.state)
            }
            .widgetURL(WidgetLinks.home)
        }
        .configurationDisplayName("场景")
        .description("各场景当前使用的地区与节点。")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    ScenesWidget()
} timeline: {
    SharedEntry(date: .now, state: .prototype())
}
