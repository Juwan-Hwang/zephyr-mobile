// 首页底部指令栏（原型 `.dock`：52 高玻璃胶囊 “🔍 搜索或输入指令” + 右侧 52pt 玻璃圆形资料库按钮，间距 10）。
// 两种模式：
//   按钮模式 `ZSearchBar(onTap:)`：点击展开指令页（首页）。
//   输入模式 `ZSearchBar(text:isFocused:)`：指令页顶部的真实输入框（原型 `.cin` 56 高、--s3 底、17 号字）。
// 资料库按钮可选；按下缩放 + 触感；大字体时高度随字号增长。

import SwiftUI

public struct ZSearchBar: View {
    private let placeholder: LocalizedStringKey
    private let text: Binding<String>?
    private let isFocused: FocusState<Bool>.Binding?
    private let onTap: (() -> Void)?
    private let onSubmit: (() -> Void)?
    private let libraryLabel: LocalizedStringKey
    private let libraryAction: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = ZMetrics.dockHeight

    /// 按钮模式（首页）。
    public init(placeholder: LocalizedStringKey = "搜索或输入指令",
                libraryLabel: LocalizedStringKey = "资料库",
                onTap: @escaping () -> Void,
                libraryAction: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self.text = nil
        self.isFocused = nil
        self.onTap = onTap
        self.onSubmit = nil
        self.libraryLabel = libraryLabel
        self.libraryAction = libraryAction
    }

    /// 输入模式（指令页）。
    public init(text: Binding<String>,
                isFocused: FocusState<Bool>.Binding,
                placeholder: LocalizedStringKey = "搜索或输入指令",
                onSubmit: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self.text = text
        self.isFocused = isFocused
        self.onTap = nil
        self.onSubmit = onSubmit
        self.libraryLabel = "资料库"
        self.libraryAction = nil
    }

    public var body: some View {
        HStack(spacing: ZTokens.Space.n3 + ZTokens.Space.n1 / 2) {
            if let text, let isFocused {
                field(text: text, isFocused: isFocused)
            } else {
                Button { onTap?() } label: { capsuleContent { placeholderText } }
                    .buttonStyle(ZPressStyle(haptic: .none))
                    .accessibilityLabel(Text(placeholder))
                    .accessibilityAddTraits(.isSearchField)
            }
            if let libraryAction {
                ZIconButton(systemImage: "square.grid.2x2", label: libraryLabel, style: .glass, action: libraryAction)
                    .frame(width: height, height: height)
            }
        }
    }

    private var placeholderText: some View {
        Text(placeholder)
            .foregroundStyle(ZColor.t3)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(text: Binding<String>, isFocused: FocusState<Bool>.Binding) -> some View {
        capsuleContent {
            TextField(placeholder, text: text)
                .focused(isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { onSubmit?() }
                .foregroundStyle(ZTokens.Colors.screenT1)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ZColor.t3)
                        .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .none))
                .accessibilityLabel(Text("清除"))
            }
        }
    }

    private func capsuleContent<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: ZTokens.Space.n3 + ZTokens.Space.n1 / 2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ZColor.t3)
                .accessibilityHidden(true)
            content()
        }
        .zType(.body)
        .padding(.horizontal, ZTokens.Space.n5 + ZTokens.Space.n1 / 2)
        .frame(maxWidth: .infinity, minHeight: height)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay { Capsule(style: .continuous).fill(ZCardFill()) }
        }
        .overlay { Capsule(style: .continuous).strokeBorder(ZTokens.Colors.screenHl, lineWidth: ZMetrics.hairline) }
        .contentShape(Capsule(style: .continuous))
    }
}

#if DEBUG
private struct ZSearchBarSample: View {
    @State private var query = "日本 视频"
    @FocusState private var focused: Bool
    var body: some View {
        ZSearchBar(onTap: {}, libraryAction: {})
        ZSearchBar(onTap: {})
        ZSearchBar(text: $query, isFocused: $focused)
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZSearchBarSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZSearchBarSample() } }
#Preview("强调色") { ZAccentMatrix { ZSearchBar(onTap: {}, libraryAction: {}) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZSearchBarSample() } }
