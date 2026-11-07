// 时间线：所有主屏 / 锁屏小组件共用，数据来自 App Group 的 SharedState。
//
// 策略：一条“现在”的条目，15 分钟后再要时间线（系统预算内的合理节奏）；
// 真正的刷新由 App 主动触发：连接状态 / 模式 / 场景 / 强调色变化时 WidgetCenter.reloadAllTimelines()（AppServices）。
// 今日用量跨零点时，在零点追加一条条目，让柱状图归零而不是显示昨天的数据。

import SwiftUI
import WidgetKit
import ZephyrDesign

struct SharedEntry: TimelineEntry {
    let date: Date
    let state: SharedState
}

struct SharedTimelineProvider: TimelineProvider {
    static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> SharedEntry {
        SharedEntry(date: Date(), state: .prototype())
    }

    func getSnapshot(in context: Context, completion: @escaping (SharedEntry) -> Void) {
        let now = Date()
        let state = context.isPreview ? SharedState.prototype(now: now) : SharedStore.shared.read()
        completion(SharedEntry(date: now, state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SharedEntry>) -> Void) {
        completion(Self.timeline(state: SharedStore.shared.read(), now: Date()))
    }

    static func timeline(state: SharedState, now: Date, calendar: Calendar = .current) -> Timeline<SharedEntry> {
        var entries = [SharedEntry(date: now, state: state)]
        let next = now.addingTimeInterval(refreshInterval)
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime),
           midnight < next {
            entries.append(SharedEntry(date: midnight, state: state))
        }
        return Timeline(entries: entries, policy: .after(next))
    }
}

/// 小组件统一外壳：背景 + 外边距由系统 containerBackground 处理。
struct WidgetContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.containerBackground(for: .widget) {
            ZTokens.Colors.screenS1
        }
    }
}
