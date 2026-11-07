// 预览辅助（仅 DEBUG）：统一的纯黑/浅灰底、四种强调色并排、AX5 大字体。
// 组件本身不依赖引擎，所以预览不注入 MockEngine；页面级预览由 ZephyrFeatures 负责注入。

#if DEBUG
import SwiftUI

/// 预览画布：页面底色 + 默认内边距 + 可选外观/字号/强调色。
struct ZPreviewCanvas<Content: View>: View {
    var scheme: ColorScheme = .dark
    var dynamicType: DynamicTypeSize = .large
    var accent: ZTokens.Accent = .blue
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZTokens.Space.n5) { content() }
                .padding(ZTokens.Layout.pageMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .zPageBackground()
        .zAccent(accent)
        .dynamicTypeSize(dynamicType)
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(scheme)
    }
}

/// 四种强调色纵向排列。
struct ZAccentMatrix<Content: View>: View {
    var scheme: ColorScheme = .dark
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZTokens.Space.n6) {
                ForEach(ZTokens.Accent.allCases, id: \.self) { accent in
                    VStack(alignment: .leading, spacing: ZTokens.Space.n3) {
                        Text(verbatim: accent.rawValue)
                            .zMono(.small)
                            .foregroundStyle(ZTokens.Colors.screenT3)
                        VStack(alignment: .leading, spacing: ZTokens.Space.n3) { content() }
                    }
                    .zAccent(accent)
                }
            }
            .padding(ZTokens.Layout.pageMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .zPageBackground()
        .environment(\.colorScheme, scheme)
        .preferredColorScheme(scheme)
    }
}
#endif
