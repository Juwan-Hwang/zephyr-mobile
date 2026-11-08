// SubscriptionDiffCard — 订阅更新的 diff 卡（原型 .diff）：
//   Nebula Cloud 已更新                2 小时前
//   +1,204     −318     0
//   节点        节点      规则变更
//   ──────────────────────────────
//   ● 覆写已保留 · 场景池已重新检测
// 订阅页顶部（最近一次更新）与“更新前显示更改”的确认 sheet 共用。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct SubscriptionDiffCard: View {
    var title: String
    var trailing: String?
    var diff: SubscriptionDiff
    /// true = 预览（尚未应用），状态行用将来时。
    var isPreview = false

    var body: some View {
        ZCard {
            VStack(alignment: .leading, spacing: ZTokens.Space.n4) {
                HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                    Text(verbatim: title)
                        .zType(.headline)
                        .fontWeight(.regular)
                        .foregroundStyle(ZTokens.Colors.screenT1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let trailing {
                        Text(verbatim: trailing)
                            .zMono(.small)
                            .foregroundStyle(ZTokens.Colors.screenT3)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: ZTokens.Space.n6) { numbers }
                    VStack(alignment: .leading, spacing: ZTokens.Space.n3) { numbers }
                }
                ZDivider()
                HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3) {
                    ZStatusDot(isOn: true, color: diff.overridesKept ? ZSwitchColor.on : ZTokens.Colors.screenAmber)
                    Text(verbatim: status)
                        .zType(.footnote)
                        .foregroundStyle(ZTokens.Colors.screenT2)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var numbers: some View {
        ZBigNumber(SubscriptionsModel.signed(diff.addedNodes, plus: true), size: .compact, caption: "节点",
                   tone: ZTokens.Colors.screenGreen,
                   accessibilityLabel: Text("新增 \(ZFormat.count(diff.addedNodes)) 个节点"))
        ZBigNumber(SubscriptionsModel.signed(diff.removedNodes, plus: false), size: .compact, caption: "节点",
                   tone: ZTokens.Colors.screenRed,
                   accessibilityLabel: Text("移除 \(ZFormat.count(diff.removedNodes)) 个节点"))
        ZBigNumber(ZFormat.count(diff.ruleChanges), size: .compact, caption: "规则变更")
    }

    private var status: String {
        var parts: [String] = []
        if isPreview {
            parts.append(ZL.tr(diff.overridesKept ? "覆写将保留" : "部分覆写将失效"))
            if diff.scenesRetested { parts.append(ZL.tr("场景池将重新检测")) }
        } else {
            parts.append(ZL.tr(diff.overridesKept ? "覆写已保留" : "部分覆写已失效"))
            if diff.scenesRetested { parts.append(ZL.tr("场景池已重新检测")) }
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    VStack(spacing: ZTokens.Space.n5) {
        SubscriptionDiffCard(title: "Nebula Cloud 已更新", trailing: "2 小时前",
                             diff: SubscriptionDiff(addedNodes: 1204, removedNodes: 318, ruleChanges: 0,
                                                    overridesKept: true, scenesRetested: true))
        SubscriptionDiffCard(title: "将更新 Orbit", diff: SubscriptionDiff(addedNodes: 12, removedNodes: 3, ruleChanges: 2,
                                                                         overridesKept: false, scenesRetested: false),
                             isPreview: true)
    }
    .padding()
    .zPageBackground()
    .preferredColorScheme(.dark)
}
