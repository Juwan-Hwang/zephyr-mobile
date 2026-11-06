// WidgetsGuideSheet — 资料库“小组件与控制中心”：说明如何添加主屏小组件、锁屏小组件与控制中心开关。
// 用 `.zSheet(isPresented:detents:)` 呈现。系统不允许 App 直接替用户添加小组件，因此这里只给步骤（文案与 Widgets 扩展的能力一致）。

import SwiftUI
import ZephyrDesign

struct WidgetsGuideSheet: View {
    private struct Step: Identifiable {
        var id: Int
        var title: LocalizedStringKey
        var detail: LocalizedStringKey
    }

    private let steps: [Step] = [
        Step(id: 0, title: "主屏幕小组件", detail: "长按主屏幕空白处 › 左上角“编辑” › 添加小组件 › 搜索 Zephyr。小号显示连接状态，中号加上实时速率。"),
        Step(id: 1, title: "锁定屏幕", detail: "长按锁定屏幕 › 自定 › 锁定屏幕 › 添加小组件 › Zephyr。连接时会显示实时活动。"),
        Step(id: 2, title: "控制中心", detail: "从右上角向下轻扫打开控制中心 › 左上角“+” › 添加控制 › Zephyr。需要 iOS 18。"),
    ]

    var body: some View {
        ZSheet("小组件与控制中心") {
            VStack(alignment: .leading, spacing: ZTokens.Space.n5) {
                ForEach(steps) { s in
                    ZCard {
                        VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
                            Text(s.title)
                                .zType(.headline)
                                .foregroundStyle(ZTokens.Colors.textPrimary)
                            Text(s.detail)
                                .zType(.footnote)
                                .foregroundStyle(ZTokens.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.top, ZTokens.Space.n5)
            .padding(.bottom, PageMetrics.bottomInset)
        }
    }
}

#Preview {
    Color.clear.zSheet(isPresented: .constant(true), detents: [.medium, .large]) { WidgetsGuideSheet() }
        .preferredColorScheme(.dark)
}
