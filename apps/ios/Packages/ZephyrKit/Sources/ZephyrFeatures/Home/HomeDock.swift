// 首页底部浮动栏（原型 `.dock`）：D 的 ZSearchBar 按钮模式——玻璃胶囊"搜索或输入指令" + 玻璃圆形资料库按钮。
// 轻点胶囊展开全屏指令层（CommandView），与原型一致。

import SwiftUI
import ZephyrDesign

@MainActor
struct HomeDock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZSearchBar(onTap: { model.openCommand() },
                   libraryAction: { model.present(.library) })
            .padding(.horizontal, HMetrics.cardInset)
            .padding(.bottom, HMetrics.dockBottom)
    }
}

/// 底部渐隐，让滚动内容在指令栏后面淡出（原型 `.fade`）。
@MainActor
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
