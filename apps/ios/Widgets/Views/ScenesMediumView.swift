// 中号主屏小组件：场景列表（AI / 视频 / 其他 → 地区徽标、当前节点、延迟），原型 shots/hs.png 中部。
// 每行是一个 Link，打开对应场景详情（zephyr://scene/<id>）。

import SwiftUI
import ZephyrDesign
import ZephyrKit

struct ScenesMediumView: View {
    var state: SharedState
    static let maxRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: ZTokens.Space.n2) {
            Text("场景")
                .zType(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(ZTokens.Colors.screenT2)
            if state.scenes.isEmpty {
                Spacer(minLength: 0)
                Text("添加订阅后，这里会显示各场景的出口")
                    .zType(.footnote)
                    .foregroundStyle(ZTokens.Colors.screenT3)
                Spacer(minLength: 0)
            } else {
                let rows = Array(state.scenes.prefix(Self.maxRows))
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, scene in
                    if index > 0 {
                        Rectangle().fill(ZTokens.Colors.screenHl).frame(height: 1).accessibilityHidden(true)
                    }
                    Link(destination: WidgetLinks.scene(scene.id)) {
                        SceneRow(scene: scene, columnNames: rows.map(\.name))
                    }
                }
            }
        }
        .dynamicTypeSize(...WidgetStyle.maxDynamicType)
    }
}

private struct SceneRow: View {
    var scene: SharedState.SceneSummary
    /// 本组件里所有行的场景名：用来把名字列撑到“最长名”的宽度，三行的徽标列因此对齐（REVIEW-Q1 W-P2-7）。
    var columnNames: [String]
    /// 名字列上限：超长的自定义场景名在这里截断，给节点名留出空间（原型 `.sr span` 40，约 3 倍）。
    @ScaledMetric(relativeTo: .body) private var nameMaxWidth: CGFloat = 120

    var body: some View {
        HStack(spacing: ZTokens.Space.n3) {
            // 隐藏的“最长名”占位 + 可见名字叠在一起：不需要测量，宽度天然等于最长者，且随 Dynamic Type 变化。
            ZStack(alignment: .leading) {
                ForEach(Array(columnNames.enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name).zType(.body).lineLimit(1).hidden()
                }
                Text(verbatim: scene.name)
                    .zType(.body)
                    .foregroundStyle(ZTokens.Colors.screenT2)
                    .lineLimit(1)
            }
            .frame(maxWidth: nameMaxWidth, alignment: .leading)
            .layoutPriority(1)
            RegionBadge(region: scene.region)
            Text(scene.nodeName)
                .zType(.body)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: ZTokens.Space.n1)
            LatencyText(ms: scene.latencyMs)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scene.name)，\(scene.nodeName)，\(ZFormat.latency(scene.latencyMs.map { Int32(clamping: $0) }))")
    }
}

/// “61 ms”：数字正文、单位小号；超时警告色。
struct LatencyText: View {
    var ms: Int?

    var body: some View {
        if let ms, ms >= 0 {
            HStack(alignment: .firstTextBaseline, spacing: ZTokens.Space.n1 / 2) {
                Text("\(ms)").zType(.body, monospacedDigits: true)
                Text("ms").zType(.caption)
            }
            .foregroundStyle(ZTokens.Colors.screenT2)
        } else {
            Text(ms == nil ? LocalizedStringKey("—") : LocalizedStringKey("超时"))
                .zType(.footnote)
                .foregroundStyle(ms == nil ? ZTokens.Colors.screenT3 : ZTokens.Colors.screenAmber)
        }
    }
}

#Preview {
    ScenesMediumView(state: .prototype())
        .padding(ZTokens.Space.n5)
        .frame(width: 364, height: 170)
        .background(ZTokens.Colors.screenS1)
        .clipShape(RoundedRectangle(cornerRadius: ZTokens.Radius.overlay, style: .continuous))
}
