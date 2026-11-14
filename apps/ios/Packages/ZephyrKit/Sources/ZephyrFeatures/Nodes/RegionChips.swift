// RegionChips — 地区筛选（原型 .chips）：“全部” + “US 312 万”……；选中项实心反色。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct RegionChips: View {
    var sections: [RegionSection]
    var selected: String
    var onSelect: (String) -> Void

    /// 30pt 视觉 + 2×n1 内边距 = 38pt；外扩 3pt → 44pt。
    static let hitOutset: CGFloat = 3

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ZTokens.Space.n3) {
                chip(code: "", title: ZL.tr("全部"), count: nil)
                ForEach(sections) { s in
                    chip(code: s.region, title: s.region, count: CompactCount.chip(s.count))
                }
            }
            .padding(.horizontal, PageMetrics.margin)
            .padding(.vertical, ZTokens.Space.n1)
        }
        .sensoryFeedback(.selection, trigger: selected)
        .scrollClipDisabled()
    }

    private func chip(code: String, title: String, count: String?) -> some View {
        let on = selected.caseInsensitiveCompare(code) == .orderedSame
        return Button { onSelect(code) } label: {
            HStack(spacing: ZTokens.Space.n2) {
                Text(title).zType(.footnote)
                if let count {
                    Text(count)
                        .zMono(.micro)
                        .opacity(0.6)
                }
            }
            .foregroundStyle(on ? ZPage.background : ZColor.t2)
            .padding(.horizontal, ZTokens.Space.n4)
            .frame(minHeight: ZTokens.Space.n7 - 2)
            .background {
                Capsule().fill(on ? ZTokens.Colors.screenT1 : .clear)
            }
            .overlay {
                Capsule().strokeBorder(on ? .clear : ZTokens.Colors.screenHl2, lineWidth: 1)
            }
            .padding(.vertical, ZTokens.Space.n1)
            // 触控区 30 + 4×2 = 38pt，再向外扩 3pt 到 44pt（HIG 最小触控），不改布局与视觉（REVIEW-Q1 L-P2-9）。
            .contentShape(Rectangle().inset(by: -Self.hitOutset))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { ZL.s("%1$@，%2$@个节点", title, "\($0)") } ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

#Preview {
    RegionChips(sections: [
        RegionSection(region: "US", name: "美国", count: 3_118_402, rowOffset: 0),
        RegionSection(region: "JP", name: "日本", count: 2_204_117, rowOffset: 3_118_403),
        RegionSection(region: "HK", name: "香港", count: 1_906_551, rowOffset: 5_322_521),
    ], selected: "JP", onSelect: { _ in })
    .zPageBackground()
    .preferredColorScheme(.dark)
}
