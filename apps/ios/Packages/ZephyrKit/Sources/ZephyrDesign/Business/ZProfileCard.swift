// 订阅（配置）行（原型订阅页 “流量” 与首页 “订阅”）：
// 左 “Nebula Cloud” + “8,204 个节点 · 26 天后到期” 13 t3 + 用量条（将用尽时黄色）；
// 右 “86.4 GB”（等宽）+ “剩余”。可带右箭头（“其他 212 个 ›”）。
// 与 ZGroupCard 一样不带背景：放进 `ZCard(padding: 0)`，行间 ZDivider。AX 尺寸上下堆叠。

import SwiftUI
import ZephyrKit

public struct ZProfileCard: View {
    private let name: String
    private let detail: String?
    private let remaining: String?
    private let remainingCaption: String?
    private let usage: Double?
    private let isWarning: Bool
    private let showsChevron: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// - Parameters:
    ///   - detail: "8,204 个节点 · 26 天后到期"。
    ///   - remaining: 剩余流量（已格式化，如 `ZFormat.bytes(...)` → "86.4 GB"）。
    ///   - remainingCaption: 剩余下方小字，默认 "剩余"；首页可传 "26 天后到期"。
    ///   - usage: 已用比例 0...1，nil 不画条。
    ///   - isWarning: 将用尽/将到期：条与说明变黄。
    public init(name: String,
                detail: String? = nil,
                remaining: String? = nil,
                remainingCaption: String? = ZL.tr("剩余"),
                usage: Double? = nil,
                isWarning: Bool = false,
                showsChevron: Bool = false) {
        self.name = name
        self.detail = detail
        self.remaining = remaining
        self.remainingCaption = remainingCaption
        self.usage = usage
        self.isWarning = isWarning
        self.showsChevron = showsChevron
    }

    public var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: ZTokens.Space.n3))
                             : AnyLayout(HStackLayout(alignment: .center, spacing: ZTokens.Space.n5))
        layout {
            VStack(alignment: .leading, spacing: ZTokens.Space.n1) {
                Text(verbatim: name)
                    .zType(.headline)
                    .fontWeight(.regular)
                    .foregroundStyle(ZTokens.Colors.screenT1)
                if let detail {
                    Text(verbatim: detail)
                        .zType(.footnote)
                        .foregroundStyle(ZColor.t3)
                }
                if let usage {
                    ZProgressBar(value: usage, tone: isWarning ? .warning : .neutral, thickness: .regular, label: "已用流量")
                        .padding(.top, ZTokens.Space.n2)
                }
            }
            .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)

            if remaining != nil || showsChevron {
                HStack(spacing: ZTokens.Space.n3) {
                    if let remaining {
                        VStack(alignment: stacked ? .leading : .trailing, spacing: ZTokens.Space.n1 / 2) {
                            Text(verbatim: remaining)
                                .zMono(.large)
                                .foregroundStyle(ZTokens.Colors.screenT1)
                            if let remainingCaption {
                                Text(verbatim: remainingCaption)
                                    .zType(.caption)
                                    .foregroundStyle(isWarning ? ZTokens.Colors.screenAmber : ZColor.t3)
                            }
                        }
                    }
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(ZQuaternaryText())
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.horizontal, ZTokens.Space.n5)
        .padding(.vertical, ZTokens.Space.n4 + ZTokens.Space.n1 / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private struct ZProfileSample: View {
    var body: some View {
        ZCard(padding: 0) {
            VStack(spacing: 0) {
                ZProfileCard(name: "Nebula Cloud", detail: "8,204 个节点 · 26 天后到期", remaining: "86.4 GB", usage: 0.56)
                ZDivider()
                ZProfileCard(name: "Orbit", detail: "3,118 个节点 · 11月9日到期", remaining: "12.0 GB", usage: 0.88, isWarning: true)
                ZDivider()
                ZProfileCard(name: "其他 212 个", detail: "13,098,480 个节点", showsChevron: true)
            }
        }
    }
}
#endif

#Preview("深色") { ZPreviewCanvas { ZProfileSample() } }
#Preview("浅色") { ZPreviewCanvas(scheme: .light) { ZProfileSample() } }
#Preview("强调色") { ZAccentMatrix { ZCard(padding: 0) { ZProfileCard(name: "Nebula Cloud", remaining: "86.4 GB", remainingCaption: "26 天后到期", usage: 0.4) } } }
#Preview("AX5") { ZPreviewCanvas(dynamicType: .accessibility5) { ZProfileSample() } }
