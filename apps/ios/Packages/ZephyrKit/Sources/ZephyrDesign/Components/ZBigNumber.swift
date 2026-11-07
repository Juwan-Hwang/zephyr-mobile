// 超大细数字 + 单位（原型 `.big b` 76/200、`.pgh .ct b` 44/200、`.spd b` 56/200、`.diff .rw b` 22/300）。
// 等宽数字、负字距；数值变化用 numericText 过渡（Reduce Motion 下直接替换）。
// 大字体：单位放不下时换到下一行（ViewThatFits），数字本身单行 + 最小缩放。

import SwiftUI

public struct ZBigNumber: View {
    private let value: String
    private let unit: String?
    private let size: ZDisplaySize
    private let caption: LocalizedStringKey?
    private let tone: Color?
    private let a11yLabel: Text?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: 已格式化好的数字，如 `ZFormat.count(13_109_802)` → "13,109,802"。
    ///   - unit: 数字右侧的单位（"条"、"MB/s"、"GB"）。
    ///   - caption: 数字下方的小字说明（"节点"、"规则变更"）。
    ///   - tone: 数字颜色（默认 textPrimary；diff 用 textSuccess / textDanger）。
    ///   - accessibilityLabel: 朗读文本；默认读 “value unit caption”。
    public init(_ value: String,
                unit: String? = nil,
                size: ZDisplaySize = .title,
                caption: LocalizedStringKey? = nil,
                tone: Color? = nil,
                accessibilityLabel: Text? = nil) {
        self.value = value
        self.unit = unit
        self.size = size
        self.caption = caption
        self.tone = tone
        self.a11yLabel = accessibilityLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: unitSpacing) {
                    number
                    unitText
                }
                VStack(alignment: .leading, spacing: 0) {
                    number
                    unitText
                }
            }
            if let caption {
                Text(caption)
                    .zType(.caption)
                    .foregroundStyle(ZTokens.Colors.screenT3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel ?? defaultLabel)
    }

    private var number: some View {
        Text(verbatim: value)
            .zDisplay(size)
            .foregroundStyle(tone ?? ZTokens.Colors.screenT1)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : ZMotion.slow, value: value)
    }

    @ViewBuilder
    private var unitText: some View {
        if let unit {
            Text(verbatim: unit)
                .zType(size == .hero ? .body : .footnote)
                .foregroundStyle(size == .hero ? ZTokens.Colors.screenT2 : ZTokens.Colors.screenT3)
                .lineLimit(1)
        }
    }

    private var unitSpacing: CGFloat {
        size == .hero ? ZTokens.Space.n4 : ZTokens.Space.n3
    }

    private var defaultLabel: Text {
        var parts = [value]
        if let unit { parts.append(unit) }
        let base = Text(verbatim: parts.joined(separator: " "))
        if let caption { return base + Text(verbatim: " ") + Text(caption) }
        return base
    }
}

#if DEBUG
private struct ZBigNumberSample: View {
    var body: some View {
        ZBigNumber("13,109,802", unit: "个", size: .hero)
        ZBigNumber("103,606,731", unit: "条", size: .title)
        ZBigNumber("2.8", unit: "MB/s", size: .large)
        HStack(spacing: ZTokens.Space.n5) {
            ZBigNumber("+1,204", size: .compact, caption: "节点", tone: ZTokens.Colors.screenGreen)
            ZBigNumber("−318", size: .compact, caption: "节点", tone: ZTokens.Colors.screenRed)
            ZBigNumber("0", size: .compact, caption: "规则变更")
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZBigNumberSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZBigNumberSample() } }
#Preview("强调色") { ZAccentMatrix { ZBigNumber("38", unit: "ms", size: .metric, tone: ZTokens.Accent.blue.color) } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZBigNumberSample() } }
