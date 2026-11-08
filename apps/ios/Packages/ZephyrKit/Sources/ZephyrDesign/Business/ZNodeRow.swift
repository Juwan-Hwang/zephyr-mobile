// 节点行（原型 `.vr`：52 高、左 22 / 右 44（给索引条让位）、列间距 12、名称 15 号（左内 2）单行省略、搜索命中词强调色、
// 倍率 “×1.5” 等宽 12 t3、协议等宽 10.5 t3 字距 .02em、延迟等宽 13 列宽 52（<200 t2 / ≥200 琥珀 / 未测 t4）；底部 1px --hl 分隔线从 22 起）。
// 大字体（≥ xxLarge，与节点页 UIKit 列表 NodeListStyle.isXL 同阈值，原型 `.device.xl .vr`）：66 高、名称封顶 19、延迟 16、隐藏协议。
// 固定行高下字号封顶（名称 17 / xl 19，延迟 14 / xl 16），与 NodeListStyle 一致，SwiftUI 与 UIKit 两条渲染路径同一套数值。
// 为 1e8 行虚拟列表设计：无状态、无 GeometryReader、无动画，适合 UIHostingConfiguration 复用。

import SwiftUI

public struct ZNodeRow: View {
    private let name: String
    private let highlights: [String]
    private let protocolName: String?
    private let multiplier: String?
    private let latency: Int?
    private let isTesting: Bool
    private let isSelected: Bool
    private let regionCode: String?
    private let trailingInset: CGFloat
    @Environment(\.zAccent) private var accent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var nameSize: CGFloat = ZTokens.TypeStyle.zRowValue.size

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
        self.init(name: name, highlights: highlight.map { [$0] } ?? [], protocolName: protocolName, multiplier: multiplier,
                  latency: latency, isTesting: isTesting, isSelected: isSelected, regionCode: regionCode,
                  trailingInset: trailingInset)
    }

    /// 多个搜索词（如 “东京 iplc” 拆词后逐个高亮，与节点页 NodeNameMarkup 一致）。`highlights` 无默认值，避免与上面的初始化重载歧义。
    public init(name: String,
                highlights: [String],
                protocolName: String? = nil,
                multiplier: String? = nil,
                latency: Int?,
                isTesting: Bool = false,
                isSelected: Bool = false,
                regionCode: String? = nil,
                trailingInset: CGFloat = ZTokens.Layout.touchMinIos) {
        self.name = name
        self.highlights = highlights
        self.protocolName = protocolName
        self.multiplier = multiplier
        self.latency = latency
        self.isTesting = isTesting
        self.isSelected = isSelected
        self.regionCode = regionCode
        self.trailingInset = trailingInset
    }

    /// 是否按原型 xl 排版（与 NodeListStyle：`preferredContentSizeCategory >= .extraExtraLarge` 一致）。
    public static func isLarge(_ size: DynamicTypeSize) -> Bool { size >= .xxLarge }

    /// 行高：列表布局用（与视图内部一致）。
    public static func height(for size: DynamicTypeSize) -> CGFloat {
        isLarge(size) ? ZMetrics.rowHeightLarge : ZTokens.Layout.rowHeight
    }

    public var body: some View {
        let large = Self.isLarge(dynamicTypeSize)
        HStack(spacing: ZTokens.Space.n4) {
            if let regionCode { ZFlag(regionCode).dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
            HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n1) {
                Text(attributedName)
                    .font(.system(size: min(nameSize, large ? ZMetrics.nodeNameCapLarge : ZMetrics.nodeNameCap)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let multiplier {
                    Text(verbatim: multiplier)
                        .modifier(ZMonoModifier(.small, weight: .regular, maxSize: ZMetrics.nodeLatencyCap))
                        .foregroundStyle(ZColor.t3)
                        .fixedSize()
                }
            }
            .padding(.leading, ZMetrics.nodeNameLead)
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent.color)
            }
            if let protocolName, !large {
                Text(verbatim: protocolName)
                    .modifier(ZMonoModifier(.micro, weight: .regular, maxSize: ZMetrics.monoMicro))
                    .tracking(ZMetrics.monoMicro * 0.02)
                    .foregroundStyle(ZColor.t3)
                    .fixedSize()
            }
            ZLatencyPill(ms: latency, isTesting: isTesting,
                         maxFontSize: large ? ZMetrics.nodeLatencyCapLarge : ZMetrics.nodeLatencyCap,
                         columnWidth: large ? ZMetrics.rowHeightLarge : ZMetrics.latencyColumn)
                .fixedSize()
        }
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
        s.foregroundColor = ZTokens.Colors.screenT1
        for term in highlights where !term.isEmpty {
            var searchStart = s.startIndex
            while searchStart < s.endIndex,
                  let range = s[searchStart...].range(of: term, options: .caseInsensitive) {
                s[range].foregroundColor = accent.color
                searchStart = range.upperBound
            }
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
            ZNodeRow(name: "东京 IPLC 东京", highlights: ["东京", "iplc"], protocolName: "VLESS", latency: 212)
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZNodeRowSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZNodeRowSample() } }
#Preview("强调色") { ZAccentMatrix { ZNodeRow(name: "东京 IPLC 12", highlight: "IPLC", latency: 64, isSelected: true) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZNodeRowSample() } }
