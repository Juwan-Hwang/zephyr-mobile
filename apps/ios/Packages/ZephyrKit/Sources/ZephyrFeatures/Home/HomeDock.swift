// 首页底部浮动栏（原型 `.dock`）：玻璃胶囊"搜索或输入指令" + 玻璃圆形资料库按钮。
// 搜索栏是一个按钮：轻点展开全屏指令层（CommandView），与原型一致。待替换为 D 的 ZSearchBar（按钮形态）。

import SwiftUI
import ZephyrDesign

struct HomeDock: View {
    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var height = HMetrics.dockHeight

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            Button {
                model.openCommand()
            } label: {
                HStack(spacing: ZTokens.Space.n3) {
                    Image(systemName: "magnifyingglass")
                    Text(verbatim: "搜索或输入指令").lineLimit(1)
                    Spacer(minLength: 0)
                }
                .zType(.body)
                .foregroundStyle(ZTokens.Colors.textTertiary)
                .padding(.horizontal, ZTokens.Space.n5)
                .frame(maxWidth: .infinity, minHeight: height)
                .zSurface(.glass, cornerRadius: height / 2)
                .contentShape(Capsule())
            }
            .buttonStyle(ZPressStyle(haptic: .light))
            .accessibilityLabel(Text(verbatim: "搜索或输入指令"))
            .accessibilityAddTraits(.isSearchField)

            ZIconButton(systemImage: "square.grid.2x2", label: "资料库", style: .glass) {
                model.present(.library)
            }
        }
        .padding(.horizontal, HMetrics.cardInset)
        .padding(.bottom, HMetrics.dockBottom)
    }
}

/// 底部渐隐，让滚动内容在指令栏后面淡出（原型 `.fade`）。
struct HomeBottomFade: View {
    var body: some View {
        LinearGradient(colors: [ZPage.background.opacity(0), ZPage.background], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    HPreview(model: .preview()) {
        VStack { Spacer(); HomeDock() }
    }
}
