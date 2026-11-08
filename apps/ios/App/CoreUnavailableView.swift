// 真核心加载失败时的整页提示（Release）。宁可明说“不可用”，也不展示演示数据（REVIEW-Q2 X-P0-2）。

import SwiftUI

struct CoreUnavailableView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("代理核心无法启动")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("请退出后重新打开 Zephyr；若问题持续，请重新安装应用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
    }
}
