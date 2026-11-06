// 设置/列表行（原型 `.gr`：最小高 56、内边距 12/14、标题 15、副标题 12 t3、右侧值 15 t3 + 箭头 t4、或开关；
// 规则 “匹配顺序” 左侧等宽序号 t4；命中行 `.gr.hit` 9% 强调色底）。
// 三种右侧：
//   accessory: .chevron / .value("家") / .valueChevron("24 小时") / .none
//   isOn:      开关（整行是系统 Toggle，VoiceOver 原生开关语义）
//   trailing:  任意视图（规则层的 ZBadge + 计数）
// AX 尺寸：右侧值换到标题下方。行不带背景，放进 ZSettingsGroup / ZCard(padding: 0)。
// 标题传数据字符串时用 `LocalizedStringKey(name)` 或 `verbatim:` 版本。

import SwiftUI

public enum ZSettingsAccessory: Sendable, Equatable {
    case none
    case chevron
    case value(String)
    case valueChevron(String)
}

public struct ZSettingsRow<Trailing: View>: View {
    private let title: Text
    private let subtitle: String?
    private let index: Int?
    private let isHighlighted: Bool
    private let toggle: Binding<Bool>?
    private let trailing: Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = ZMetrics.settingsRowMin

    /// 自定义右侧。
    public init(_ title: LocalizedStringKey,
                subtitle: String? = nil,
                index: Int? = nil,
                isHighlighted: Bool = false,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(title)
        self.subtitle = subtitle
        self.index = index
        self.isHighlighted = isHighlighted
        self.toggle = nil
        self.trailing = trailing()
    }

    /// 自定义右侧（标题为数据字符串）。
    public init(verbatim title: String,
                subtitle: String? = nil,
                index: Int? = nil,
                isHighlighted: Bool = false,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = Text(verbatim: title)
        self.subtitle = subtitle
        self.index = index
        self.isHighlighted = isHighlighted
        self.toggle = nil
        self.trailing = trailing()
    }

    fileprivate init(title: Text, subtitle: String?, index: Int?, isHighlighted: Bool, toggle: Binding<Bool>?, trailing: Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.index = index
        self.isHighlighted = isHighlighted
        self.toggle = toggle
        self.trailing = trailing
    }

    public var body: some View {
        Group {
            if let toggle {
                ZToggle(isOn: toggle) { titleBlock }
            } else {
                let stacked = dynamicTypeSize.isAccessibilitySize
                let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZTokens.Space.n2))
                                     : AnyLayout(HStackLayout(alignment: .center, spacing: ZTokens.Space.n4))
                layout {
                    titleBlock.frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
                    trailing
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, ZTokens.Space.n5 - ZTokens.Space.n1 / 2)
        .padding(.vertical, ZTokens.Space.n4)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(isHighlighted ? AnyShapeStyle(ZAccentStyle(opacity: 0.09)) : AnyShapeStyle(Color.clear))
        .contentShape(Rectangle())
    }

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n4) {
            if let index {
                Text(verbatim: "\(index)")
                    .zMono(.micro)
                    .foregroundStyle(ZQuaternaryText())
                    .frame(minWidth: ZTokens.Space.n5, alignment: .leading)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                title
                    .zType(.body)
                    .foregroundStyle(ZTokens.Colors.textPrimary)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .zType(.caption)
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                }
            }
        }
    }
}

/// `.chevron` / `.value` 等标准右侧。
public struct ZSettingsAccessoryView: View {
    let accessory: ZSettingsAccessory

    public var body: some View {
        HStack(spacing: ZTokens.Space.n2) {
            switch accessory {
            case .none:
                EmptyView()
            case .chevron:
                chevron
            case .value(let v):
                value(v)
            case .valueChevron(let v):
                value(v)
                chevron
            }
        }
    }

    private func value(_ v: String) -> some View {
        Text(verbatim: v)
            .zType(.body)
            .foregroundStyle(ZTokens.Colors.textTertiary)
            .multilineTextAlignment(.trailing)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(ZQuaternaryText())
            .accessibilityHidden(true)
    }
}

public extension ZSettingsRow where Trailing == ZSettingsAccessoryView {
    init(_ title: LocalizedStringKey, subtitle: String? = nil, index: Int? = nil,
         isHighlighted: Bool = false, accessory: ZSettingsAccessory = .chevron) {
        self.init(title: Text(title), subtitle: subtitle, index: index, isHighlighted: isHighlighted,
                  toggle: nil, trailing: ZSettingsAccessoryView(accessory: accessory))
    }

    init(verbatim title: String, subtitle: String? = nil, index: Int? = nil,
         isHighlighted: Bool = false, accessory: ZSettingsAccessory = .chevron) {
        self.init(title: Text(verbatim: title), subtitle: subtitle, index: index, isHighlighted: isHighlighted,
                  toggle: nil, trailing: ZSettingsAccessoryView(accessory: accessory))
    }
}

public extension ZSettingsRow where Trailing == EmptyView {
    /// 开关行：整行是一个系统 Toggle（绿色）。
    init(_ title: LocalizedStringKey, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.init(title: Text(title), subtitle: subtitle, index: nil, isHighlighted: false,
                  toggle: isOn, trailing: EmptyView())
    }
}

#if DEBUG
private struct ZSettingsRowSample: View {
    @State private var onDemand = true
    var body: some View {
        ZSettingsGroup {
            ZSettingsRow("按需连接", isOn: $onDemand)
            ZDivider()
            ZSettingsRow("受信任的 Wi-Fi", subtitle: "连接后自动断开", accessory: .valueChevron("家"))
            ZDivider()
            ZSettingsRow("结果保留", accessory: .valueChevron("24 小时"))
        }
        ZSettingsGroup {
            ZSettingsRow(verbatim: "Zephyr 覆写", subtitle: "在订阅之上", index: 1) {
                ZBadge("覆写", tone: .accent)
                Text(verbatim: "14").zMono(.body).foregroundStyle(ZTokens.Colors.textSecondary)
            }
            ZDivider()
            ZSettingsRow(verbatim: "OpenAI", subtitle: "规则集 · 每天更新", index: 3, isHighlighted: true) {
                ZBadge("域名")
                Text(verbatim: "312").zMono(.body).foregroundStyle(ZTokens.Colors.textSecondary)
            }
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZSettingsRowSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZSettingsRowSample() } }
#Preview("强调色") { ZAccentMatrix { ZSettingsGroup { ZSettingsRow(verbatim: "OpenAI", index: 3, isHighlighted: true, accessory: .value("312")) } } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZSettingsRowSample() } }
