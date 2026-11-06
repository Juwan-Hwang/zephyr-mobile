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
                    .foregroundStyle(ZTokens.Colors.textSecondary)
            }
            .foregroundStyle(ZTokens.Colors.textPrimary)

            let down = ZFormat.rate(state.downBps)
            HStack(alignment: .lastTextBaseline, spacing: ZTokens.Space.n3) {
                Text(down.value)
                    .zType(.metric)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("\(down.unit) ↓")
                    .zType(.body)
                    .foregroundStyle(ZTokens.Colors.textSecondary)
                Spacer(minLength: ZTokens.Space.n3)
                Text("\(ZFormat.rateString(state.upBps)) ↑")
                    .zType(.body, monospacedDigits: true)
                    .foregroundStyle(ZTokens.Colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("下行 \(ZFormat.rateString(state.downBps))，上行 \(ZFormat.rateString(state.upBps))")

            SceneChips(scenes: state.scenes)
        }
        .padding(ZTokens.Space.n5)
        .dynamicTypeSize(...WidgetStyle.maxDynamicType)
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
                        .zType(.body)
                        .foregroundStyle(ZTokens.Colors.textSecondary)
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
        .background(ZTokens.Colors.bgElevated)
        .environment(\.colorScheme, .dark)
}
