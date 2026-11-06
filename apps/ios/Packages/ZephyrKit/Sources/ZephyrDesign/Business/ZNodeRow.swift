// 节点行（原型 `.vr`：52 高、左 22 / 右 44（给索引条让位）、名称 15 号单行省略、搜索命中词强调色、
// 倍率 “×1.5” 等宽 12 t3、协议等宽 10.5 t3、延迟列 52 宽；底部 1px 分隔线从 22 起）。
// 为 1e8 行虚拟列表设计：固定高度（ZTokens.Layout.rowHeight；AX 尺寸 66 并隐藏协议，同原型 xl），
// 无状态、无 GeometryReader、无动画，适合 UIHostingConfiguration 复用。

import SwiftUI

public struct ZNodeRow: View {
    private let name: String
    private let highlight: String?
    private let protocolName: String?
    private let multiplier: String?
    private let latency: Int?
    private let isTesting: Bool
    private let isSelected: Bool
    private let regionCode: String?
    private let trailingInset: CGFloat
    @Environment(\.zAccent) private var accent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - name: 节点名（不含倍率），如 "东京 03"。
    ///   - highlight: 搜索命中的子串（大小写不敏感），以强调色显示。
    ///   - protocolName: "VLESS" / "TROJAN" / "SS"…；AX 尺寸下隐藏。
    ///   - multiplier: "×1.5"。
    ///   - latency: 毫秒；nil 未测，负数超时（见 ZLatencyPill）。
    ///   - regionCode: 显示前置 ZFlag（列表已按地区分组时一般不传）。
    ///   - trailingInset: 右侧留白，默认给索引条让位（原型 44）。
    public init(name: String,
                highlight: String? = nil,
                protocolName: String? = nil,
                multiplier: String? = nil,
                latency: Int?,
                isTesting: Bool = false,
                isSelected: Bool = false,
                regionCode: String? = nil,
                trailingInset: CGFloat = ZTokens.Layout.touchMinIos) {
        self.name = name
        self.highlight = highlight
        self.protocolName = protocolName
        self.multiplier = multiplier
        self.latency = latency
        self.isTesting = isTesting
        self.isSelected = isSelected
        self.regionCode = regionCode
        self.trailingInset = trailingInset
    }

    /// 行高：列表布局用（与视图内部一致）。
    public static func height(for size: DynamicTypeSize) -> CGFloat {
        size.isAccessibilitySize ? ZMetrics.rowHeightLarge : ZTokens.Layout.rowHeight
    }

    public var body: some View {
        let large = dynamicTypeSize.isAccessibilitySize
        HStack(spacing: ZTokens.Space.n4) {
            if let regionCode { ZFlag(regionCode) }
            HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n1) {
                Text(attributedName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let multiplier {
                    Text(verbatim: multiplier)
                        .zMono(.small)
                        .foregroundStyle(ZTokens.Colors.textTertiary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent.color)
            }
            if let protocolName, !large {
                Text(verbatim: protocolName)
                    .zMono(.micro)
                    .tracking(0.2)
                    .foregroundStyle(ZTokens.Colors.textTertiary)
                    .fixedSize()
            }
            ZLatencyPill(ms: latency, isTesting: isTesting)
                .fixedSize()
        }
        .zType(.body)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.leading, ZMetrics.rowLeading)
        .padding(.trailing, trailingInset)
        .frame(height: Self.height(for: dynamicTypeSize))
        .overlay(alignment: .bottom) {
            ZDivider(leadingInset: ZMetrics.rowLeading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var attributedName: AttributedString {
        var s = AttributedString(name)
        s.foregroundColor = ZTokens.Colors.textPrimary
        if let highlight, !highlight.isEmpty, let range = s.range(of: highlight, options: .caseInsensitive) {
            s[range].foregroundColor = accent.color
        }
        return s
    }
}

#if DEBUG
private struct ZNodeRowSample: View {
    var body: some View {
        VStack(spacing: 0) {
            ZNodeRow(name: "东京 03", protocolName: "VLESS", latency: 38, isSelected: true)
            ZNodeRow(name: "东京 IPLC 12", highlight: "iplc", protocolName: "TROJAN", multiplier: "×1.5", latency: 120)
            ZNodeRow(name: "大阪 07", protocolName: "SS", latency: 407)
            ZNodeRow(name: "名古屋 01", protocolName: "VMESS", latency: nil)
            ZNodeRow(name: "札幌 02", protocolName: "HY2", latency: nil, isTesting: true)
            ZNodeRow(name: "新加坡 02", latency: -1, regionCode: "SG")
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZNodeRowSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZNodeRowSample() } }
#Preview("强调色") { ZAccentMatrix { ZNodeRow(name: "东京 IPLC 12", highlight: "IPLC", latency: 64, isSelected: true) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZNodeRowSample() } }
