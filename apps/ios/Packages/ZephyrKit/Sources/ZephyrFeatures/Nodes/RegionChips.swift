// RegionChips — 地区筛选（原型 .chips）：“全部” + “US 312 万”……；选中项实心反色。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct RegionChips: View {
    var sections: [RegionSection]
    var selected: String
    var onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ZTokens.Space.n3) {
                chip(code: "", title: "全部", count: nil)
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
            .contentShape(Capsule())
            .padding(.vertical, ZTokens.Space.n1)   // 触控区扩到 ≥ 38pt，视觉仍为 30pt
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title)，\($0)个节点" } ?? title)
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
