// 首页顶栏（原型 `.top`）：状态点 + Zephyr 字标 + 设置按钮。只读 connection.status。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct HomeHeader: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .subheadline) private var lockupHeight: CGFloat = ZTokens.FontSize.sm

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            ZStatusDot(isOn: model.isConnected,
                       color: model.connection.status == .failed ? ZTokens.Colors.colorDanger : nil)
            ZBrandMark(.lockup)
                .frame(height: lockupHeight)
                .foregroundStyle(ZTokens.Colors.textPrimary)
            Spacer(minLength: 0)
            ZIconButton(systemImage: "sun.max", label: "设置") {
                model.push(.settings)
            }
        }
        .padding(.leading, HMetrics.homeInset)
        .padding(.trailing, ZTokens.Space.n4)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    HPreview(model: .preview()) { HomeHeader() }
}
