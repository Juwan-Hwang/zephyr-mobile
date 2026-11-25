// 首页顶栏（原型 `.top`）：状态点 + Zephyr 字标 + 设置按钮。只读 connection.status。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct HomeHeader: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .subheadline) private var lockupHeight: CGFloat = ZTokens.FontSize.sm
    /// 设置按钮的 SF Symbol：标准齿轮。
    static let settingsSymbol = "gearshape"

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ZStatusDot(isOn: model.isConnected,
                       color: model.connection.status == .failed ? ZTokens.Colors.screenRed : nil)
            ZBrandMark(.lockup)
                .frame(height: lockupHeight)
                .foregroundStyle(ZTokens.Colors.screenT1)
            Spacer(minLength: 0)
            // 设置入口用系统齿轮 gearshape。原型的太阳图形（sun.max）在真机上被当成深浅色切换（#1 真机反馈 2026-11-25），已弃用。
            ZIconButton(systemImage: HomeHeader.settingsSymbol, label: "设置") {
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

#if DEBUG
#Preview {
    HPreview(model: .preview()) { HomeHeader() }
}
#endif
