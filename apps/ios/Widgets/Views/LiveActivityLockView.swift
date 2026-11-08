// 实时活动 · 锁屏底部卡片（原型 shots/lock.png）：
//   [Z] Zephyr                 2:14:07
//   2.8  MB/s ↓            194 KB/s ↑
//   [JP] AI  [HK] 视频  [TW] 其他

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct LiveActivityLockView: View {
    var state: ZephyrActivityAttributes.ContentState
    var accent: Color
    /// 系统标记过期（App 久未更新）：速率不再可信，显示“—”与“已暂停更新”，计时器照走（REVIEW W-P1-1）。
    var isStale: Bool = false
    /// 快照测试固定“现在”，计时器渲染成静态文本；nil = 系统计时器（自动走秒，不耗电）。
    var frozenNow: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
            HStack(spacing: ZTokens.Space.n3) {
                WidgetMark()
                    .frame(height: ZTokens.Space.n5)
                Text("Zephyr")
                    .zType(.headline)
                Spacer(minLength: ZTokens.Space.n3)
                ConnectionTimer(since: state.connectedSince, frozenNow: frozenNow)
                    .zType(.headline, monospacedDigits: true)
                    .fontDesign(.monospaced)
                    .foregroundStyle(ZColor.t2)
            }
            .foregroundStyle(ZTokens.Colors.screenT1)

            if isStale {
                StaleRateLine()
            } else {
                let down = ZFormat.rate(state.downBps)
                HStack(alignment: .lastTextBaseline, spacing: ZTokens.Space.n3) {
                    Text(down.value)
                        .zType(.metric)
                        .foregroundStyle(ZTokens.Colors.screenT1)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text("\(down.unit) ↓")
                        .zType(.body)
                        .foregroundStyle(ZColor.t2)
                    Spacer(minLength: ZTokens.Space.n3)
                    Text("\(ZFormat.rateString(state.upBps)) ↑")
                        .zType(.body, monospacedDigits: true)
                        .foregroundStyle(ZColor.t2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("下行 \(ZFormat.rateString(state.downBps))，上行 \(ZFormat.rateString(state.upBps))")
            }

            SceneChips(scenes: state.scenes)
        }
        .padding(ZTokens.Space.n5)
        .dynamicTypeSize(...WidgetStyle.maxDynamicType)
    }
}

/// 过期时替代速率的一行：大号“—” + “已暂停更新”（t3）。
struct StaleRateLine: View {
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: ZTokens.Space.n3) {
            Text(verbatim: "—")
                .zType(.metric)
                .foregroundStyle(ZColor.t3)
            Text("已暂停更新")
                .zType(.body)
                .foregroundStyle(ZColor.t3)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("速率已暂停更新，打开 Zephyr 查看")
    }
}

/// 连接时长：系统 Text(.timer) 自动走秒；frozenNow 非 nil 时渲染静态 “2:14:07”。
struct ConnectionTimer: View {
    var since: Date?
    var frozenNow: Date?

    var body: some View {
        if let since {
            if let frozenNow {
                Text(ZFormat.duration(Int64(frozenNow.timeIntervalSince(since) * 1000)))
            } else {
                Text(since, style: .timer)
                    .multilineTextAlignment(.trailing)
            }
        } else {
            Text("—")
        }
    }
}

/// 场景徽标行：[JP] AI  [HK] 视频  [TW] 其他
struct SceneChips: View {
    var scenes: [SharedState.SceneSummary]

    var body: some View {
        HStack(spacing: ZTokens.Space.n4) {
            ForEach(scenes) { scene in
                HStack(spacing: ZTokens.Space.n2) {
                    RegionBadge(region: scene.region)
                    Text(scene.name)
                        .zType(.caption)
                        .foregroundStyle(ZColor.t2)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(scene.name)：\(scene.nodeName)")
            }
        }
    }
}

#Preview {
    let now = Date()
    return LiveActivityLockView(state: .prototype(now: now), accent: ZTokens.Accent.blue.color, frozenNow: now)
        .background(ZTokens.Colors.screenS1)
        .environment(\.colorScheme, .dark)
}
