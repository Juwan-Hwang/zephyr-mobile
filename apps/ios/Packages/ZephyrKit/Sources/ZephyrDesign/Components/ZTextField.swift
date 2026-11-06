// 输入框（原型 `.fs`：40 高、圆角 12、--s3 底、左侧放大镜、右侧耗时/计数小字 + 圆形清除）。
// filled = 独立搜索框（节点页）；plain = 嵌在卡片里的无底色版本（规则测试 `.rt .fs`，48 高、等宽 15）。

import SwiftUI

public enum ZTextFieldStyle: Sendable {
    case filled, plain
}

public struct ZTextField: View {
    private let placeholder: LocalizedStringKey
    @Binding private var text: String
    private let systemImage: String?
    private let style: ZTextFieldStyle
    private let monospaced: Bool
    private let trailing: String?
    private let onSubmit: (() -> Void)?
    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var filledHeight: CGFloat = ZMetrics.fieldHeight
    @ScaledMetric(relativeTo: .body) private var plainHeight: CGFloat = ZMetrics.fieldHeightLarge

    /// - Parameters:
    ///   - trailing: 右侧小字，如 "2,048 个 · 0.12 ms"。
    ///   - monospaced: 输入内容用等宽字（域名、IP）。
    public init(_ placeholder: LocalizedStringKey,
                text: Binding<String>,
                systemImage: String? = "magnifyingglass",
                style: ZTextFieldStyle = .filled,
                monospaced: Bool = false,
                trailing: String? = nil,
                onSubmit: (() -> Void)? = nil) {
        self.placeholder = placeholder
        _text = text
        self.systemImage = systemImage
        self.style = style
        self.monospaced = monospaced
        self.trailing = trailing
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            field
            if let trailing, !trailing.isEmpty {
                Text(verbatim: trailing)
                    .zMono(.small)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                        .frame(minWidth: ZTokens.Layout.touchMinIos, minHeight: ZTokens.Layout.touchMinIos)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ZPressStyle(haptic: .light))
                .accessibilityLabel(Text(verbatim: "清除"))
                .transition(.opacity)
            }
        }
        .padding(.leading, ZTokens.Space.n4)
        .padding(.trailing, text.isEmpty ? ZTokens.Space.n4 : 0)
        .frame(minHeight: style == .filled ? filledHeight : plainHeight)
        .background {
            if style == .filled {
                RoundedRectangle(cornerRadius: ZTokens.Radius.surface, style: .continuous).fill(ZTrackFill())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(ZMotion.micro, value: text.isEmpty)
    }

    private var field: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit { onSubmit?() }
            .foregroundStyle(ZTokens.Colors.textPrimary)
            .modifier(ZFieldFont(monospaced: monospaced, style: style))
    }
}

private struct ZFieldFont: ViewModifier {
    let monospaced: Bool
    let style: ZTextFieldStyle

    func body(content: Content) -> some View {
        if monospaced {
            content.zMono(style == .plain ? .large : .body)
        } else {
            content.zType(.body)
        }
    }
}

#if DEBUG
private struct ZTextFieldSample: View {
    @State private var q = ""
    @State private var host = "chat.openai.com"
    var body: some View {
        ZTextField("搜索节点、地区或协议", text: $q)
        ZTextField("搜索节点", text: $host, trailing: "2,048 个 · 0.12 ms")
        ZCard(padding: 0) {
            ZTextField("输入域名或 IP 测试规则", text: $host, style: .plain, monospaced: true)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZTextFieldSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZTextFieldSample() } }
#Preview("强调色") { ZAccentMatrix { ZTextFieldSample() } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZTextFieldSample() } }
