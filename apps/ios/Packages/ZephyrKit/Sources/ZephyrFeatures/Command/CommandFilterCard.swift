// 指令预览卡 · 场景节点过滤（契约 §15.h，原型 index.html 1046–1055）：
//   视频仅使用 4K 节点
//   22 个中 14 个支持 4K，当前节点保持不变。
//   ┌ ● 出口 IP 将更改            ┐   ← 仅当前节点不满足且有已测 4K 候选时
//   └ HK 198.51.100.9 → JP …       ┘
//   [应用]
// 当前地区没有 4K 节点（poolMatching == 0）时禁用“应用”；场景已开启时按钮为“取消仅 4K 节点”。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct CommandFilterCard: View {
    let preview: CommandModel.FilterPreview
    let isApplying: Bool
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            Text(verbatim: ZL.s("%@仅使用 4K 节点", preview.sceneName))
                .zType(.headline).fontWeight(.regular).foregroundStyle(ZTokens.Colors.screenT1)
            Text(verbatim: summary).zType(.footnote).foregroundStyle(ZColor.t3)

            if let exit = exitChange {
                VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                    HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                        Circle().fill(ZTokens.Colors.screenAmber)
                            .frame(width: ZTokens.Space.n2, height: ZTokens.Space.n2)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        Text("出口 IP 将更改").zType(.footnote).foregroundStyle(ZTokens.Colors.screenT1)
                    }
                    ExitIPLine(change: exit)
                }
                .padding(ZTokens.Space.n4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: ZTokens.Radius.md, style: .continuous).fill(ZTrackFill().opacity(0.6)))
                .padding(.top, ZTokens.Space.n4)
            }

            ZButton(LocalizedStringKey(preview.active ? "取消仅 4K 节点" : "应用"), size: .large, fullWidth: true,
                    isLoading: isApplying, action: onApply)
                .disabled(!preview.canApply)
                .padding(.top, ZTokens.Space.n5)
        }
        .padding(ZTokens.Space.n5)
        .zSurface(.raised, cornerRadius: HMetrics.cardRadius)
        .padding(.horizontal, HMetrics.cardInset)
        .accessibilityElement(children: .contain)
    }

    /// 开启且当前节点不满足时才换节点，此时给出口 IP 变化（用户点“应用”即确认，§14.y）。
    private var exitChange: ExitChange? {
        let r = preview.result
        guard !preview.active, !r.currentKept, r.suggested != nil, let x = r.change,
              x.fromIp != x.toIp || x.fromRegion != x.toRegion else { return nil }
        return x
    }

    private var summary: String {
        let r = preview.result
        if preview.active { return ZL.tr("已开启。取消后恢复使用全部节点，当前节点保持不变。") }
        if r.poolMatching == 0 { return ZL.tr("没有支持 4K 的节点") }
        if r.matching == 0 { return ZL.tr("4K 节点还没有测速，在场景中重新检测后可用。") }
        let head = ZL.f("%1$lld 个中 %2$lld 个支持 4K", Int64(r.total), Int64(r.matching))
        if r.currentKept { return ZL.s("%@，当前节点保持不变。", head) }
        if let n = r.suggested { return ZL.s("%1$@，将使用%2$@。", head, n.name) }
        return ZL.s("%@，当前节点保持不变。", head)
    }
}
