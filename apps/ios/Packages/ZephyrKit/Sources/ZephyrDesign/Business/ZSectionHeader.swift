// 分组标题（原型 `.sec`：13 号 t3，左标题右附注，上 24–30 / 下 8–10，左右 22）。
// 右侧可为纯文字（“2 小时前检测”、“从上到下”）或可点链接（“今日 1.8 GB ›”）。VoiceOver 标记为标题。

import SwiftUI

public struct ZSectionHeader: View {
    private let title: LocalizedStringKey
    private let trailing: String?
    private let action: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ title: LocalizedStringKey, trailing: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.trailing = trailing
        self.action = action
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZTokens.Space.n1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: ZTokens.Space.n3))
        layout {
            Text(title)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: ZTokens.Space.n3) }
            trailingView
        }
        .zType(.footnote)
        .padding(.horizontal, ZTokens.Space.n2)
        .padding(.top, ZTokens.Space.n6)
        .padding(.bottom, ZTokens.Space.n3)
    }

    @ViewBuilder
    private var trailingView: some View {
        if let trailing {
            if let action {
                Button(action: action) {
                    HStack(spacing: ZTokens.Space.n1) {
                        Text(verbatim: trailing)
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .foregroundStyle(ZTokens.Colors.screenT3)
                    .frame(minHeight: ZTokens.Layout.touchMinIos / 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .none))
            } else {
                Text(verbatim: trailing)
                    .foregroundStyle(ZTokens.Colors.screenT3)
            }
        }
    }
}

#if DEBUG
private struct ZSectionSample: View {
    var body: some View {
        ZSectionHeader("场景", trailing: "2 小时前检测")
        ZSectionHeader("订阅", trailing: "今日 1.8 GB") {}
        ZSectionHeader("匹配顺序", trailing: "从上到下")
        ZSectionHeader("连接")
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZSectionSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZSectionSample() } }
#Preview("强调色") { ZAccentMatrix { ZSectionHeader("场景", trailing: "10 分钟前检测") } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZSectionSample() } }
