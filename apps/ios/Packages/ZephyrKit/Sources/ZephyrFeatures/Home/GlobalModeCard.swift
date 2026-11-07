// 全局模式卡（原型 12，截图 global.png）：
//   全局模式
//   所有流量均经由东京 03。场景已暂停。
//   [使用规则模式] [更换节点]
// "更换节点"展开内联确认：建议延迟最低的另一个节点，"所有 App 的出口都将变为新加坡 02。"，
// 以及"浏览全部节点"跳到节点页。切换后给可撤销提示。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct GlobalModeCard: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var suggestion: NodeSummary?
    @State private var loading = false

    var body: some View {
        ZCard(cornerRadius: HMetrics.cardRadius) {
            VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
                Text(verbatim: "全局模式").zType(.body).foregroundStyle(ZTokens.Colors.screenT1)
                Text(verbatim: "所有流量均经由\(model.globalNode?.name ?? "当前节点")。场景已暂停。")
                    .zType(.footnote).foregroundStyle(ZTokens.Colors.screenT3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: ZTokens.Space.n3) {
                    ZButton("使用规则模式", fullWidth: true) {
                        Task { await model.setMode(.rule) }
                    }
                    ZButton("更换节点", kind: .ghost, fullWidth: true, isLoading: loading) {
                        Task { await toggleChange() }
                    }
                }
                .padding(.top, ZTokens.Space.n4)
                if expanded { confirm.transition(.opacity.combined(with: .move(edge: .top))) }
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
        .animation(ZMotion.slow, value: expanded)
    }

    @ViewBuilder
    private var confirm: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
            if let s = suggestion {
                HStack(spacing: ZTokens.Space.n3) {
                    if let cur = model.globalNode { ZFlag(cur.region) }
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(ZQuaternaryText())
                    ZFlag(s.region)
                    Text(verbatim: s.name).zType(.footnote).foregroundStyle(ZTokens.Colors.screenT1)
                    if let ms = s.latencyMs, ms >= 0 {
                        Text(verbatim: ZFormat.latency(ms)).zMono(.small).foregroundStyle(ZTokens.Colors.screenT3)
                    }
                }
                .padding(.top, ZTokens.Space.n4)
                Text(verbatim: "所有 App 的出口都将变为\(s.name)。").zType(.caption).foregroundStyle(ZTokens.Colors.screenT3)
                HStack(spacing: ZTokens.Space.n3) {
                    ZButton("更改为\(s.name)", fullWidth: true) {
                        expanded = false
                        Task { await model.setGlobalNode(s) }
                    }
                    ZButton("取消", kind: .ghost, fullWidth: true) { expanded = false }
                }
                .padding(.top, ZTokens.Space.n2)
            }
            Button {
                model.push(.nodes(query: ""))
            } label: {
                Text(verbatim: "浏览全部节点").zType(.footnote).foregroundStyle(ZAccentStyle())
                    .frame(minHeight: ZTokens.Layout.touchMinIos)
            }
            .buttonStyle(ZPressStyle(haptic: .none))
        }
    }

    private func toggleChange() async {
        if expanded { expanded = false; return }
        loading = true
        suggestion = await model.globalAlternatives().first
        loading = false
        expanded = true
    }
}

#Preview {
    HPreview(model: .preview(mode: .global)) { GlobalModeCard() }
}
