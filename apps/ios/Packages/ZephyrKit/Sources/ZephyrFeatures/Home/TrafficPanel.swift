// 首页速率区（原型 `.wind`）：2.8 MB/s ↓ 大数字 + 195 KB/s ↑ + 全宽曲线。轻点 → 最近连接。
// 高频隔离：本视图只读 isConnected；速率数字在 RateReadout、曲线在 TrafficChart，两者各自读 TrafficStore。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct TrafficPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let on = model.isConnected
        Button {
            model.present(.connections(traceID: nil))
        } label: {
            ZStack(alignment: .topLeading) {
                TrafficChart(store: model.traffic, isOn: on)
                    .frame(maxWidth: .infinity)
                RateReadout(store: model.traffic)
                    .padding(.horizontal, HMetrics.homeInset)
                    .padding(.top, ZTokens.Space.n2)
                    .opacity(on ? 1 : 0)
                    .animation(ZMotion.slow, value: on)
            }
            .frame(minHeight: HMetrics.chartHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityElement(children: .contain)
        .accessibilityHint(Text(verbatim: on ? "轻点两下查看最近连接" : ""))
    }
}

/// 速率读数：每个样本（1 Hz）重算一次。
private struct RateReadout: View {
    let store: TrafficStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let down = ZFormat.rate(store.latest?.down ?? 0)
        let up = ZFormat.rate(store.latest?.up ?? 0)
        VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
            HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                Text(verbatim: down.value)
                    .zDisplay(.large)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : ZMotion.slow, value: down.value)
                HStack(spacing: ZTokens.Space.n1) {
                    Text(verbatim: down.unit)
                    Image(systemName: "arrow.down").foregroundStyle(ZTokens.Colors.colorDownload)
                }
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.textTertiary)
            }
            HStack(spacing: ZTokens.Space.n1) {
                Text(verbatim: "\(up.value) \(up.unit)")
                    .foregroundStyle(ZTokens.Colors.textSecondary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Image(systemName: "arrow.up").foregroundStyle(ZTokens.Colors.colorUpload)
            }
            .zType(.footnote, monospacedDigits: true)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "下载 \(down.value) \(down.unit)，上传 \(up.value) \(up.unit)"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("已连接") {
    HPreview(model: .preview()) { TrafficPanel() }
}

#Preview("未连接") {
    HPreview(model: .preview(connected: false)) { TrafficPanel() }
}
