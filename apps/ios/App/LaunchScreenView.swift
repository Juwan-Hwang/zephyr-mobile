// 冷启动加载画面：背景与系统启动屏（LaunchBackground）、App 背景（screenBg）一致，避免白闪 / 色差。

import SwiftUI
import ZephyrDesign

struct LaunchScreenView: View {
    var body: some View {
        ZTokens.Colors.screenBg
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .controlSize(.large)
                    .opacity(0.6)
                    .accessibilityLabel(Text("正在载入"))
            }
    }
}
