// 首页顶栏（原型 `.top`）：状态点 + Zephyr 字标 + 设置按钮。只读 connection.status。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct HomeHeader: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .subheadline) private var lockupHeight: CGFloat = ZTokens.FontSize.sm

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ZStatusDot(isOn: model.isConnected,
                       color: model.connection.status == .failed ? ZTokens.Colors.screenRed : nil)
            ZBrandMark(.lockup)
                .frame(height: lockupHeight)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Spacer(minLength: 0)
            // 设置入口沿用原型的太阳图形（品牌决定，原型 03/04 一致；REVIEW H-P2-8）。SF 里 sun.max 语义是"亮度"，
            // 所以 VoiceOver 标签明确为"设置"；若设计改为 gearshape，只改这里的符号名。
            ZIconButton(systemImage: "sun.max", label: "设置") {
                model.push(.settings)
            }
        }
        // 顶栏品牌字标与设置按钮：放大到 AX2 为止，避免字标占据半个顶栏（Q2 快照审核）。
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.leading, HMetrics.homeInset)
        .padding(.trailing, ZTokens.Space.n4)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    HPreview(model: .preview()) { HomeHeader() }
}
