// 轨迹页底部"本次连接"（原型 09 `#routeSeg` + "始终应用"开关）：
//   本次连接  [不变 | 直连 | 视频 | 其他]
//   ┌ 始终应用                 ◯ ┐
//   └ 关闭时仅更改本次连接       ┘
//
// ⚠️ 先禁用：契约 §13 的 overrideHost(host:target:sceneId:persistent:) / hostOverride(host:) 尚未进入
// Swift 协议 ZephyrEngine（见 NOTES-H.md「需要 A 补的契约」）。协议补齐后：
//   - 分段改为可选，选中即 overrideHost(host, target, sceneId, persistent: always)
//   - 打开时用 hostOverride(host) 回填当前覆写；切换后给可撤销吐司（撤销 = target .unchanged）
// 现在保持原型的版式，控件置灰并说明暂不可用，避免"点了没反应"。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct TraceOverrideSection: View {
    /// 当前命中的场景 id（不在分段里重复出现）；直连 / 拦截时为 "DIRECT" / "REJECT"。
    let currentSceneId: String?
    @Environment(AppModel.self) private var model
    @State private var always = false

    private enum Target: Hashable { case unchanged, direct, scene(String) }

    private var segments: [ZSegment<Target>] {
        var out = [ZSegment(Target.unchanged, verbatim: "不变")]
        if currentSceneId?.uppercased() != "DIRECT" { out.append(ZSegment(.direct, verbatim: "直连")) }
        for s in model.scenes where s.id != currentSceneId {
            out.append(ZSegment(.scene(s.id), verbatim: s.name))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "本次连接")
                .zType(.caption)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .padding(.horizontal, ZTokens.Space.n1)
                .padding(.top, ZTokens.Space.n6)
                .padding(.bottom, ZTokens.Space.n3)
                .accessibilityAddTraits(.isHeader)
            ZSegmented(segments, selection: .constant(Target.unchanged), label: "本次连接的路由")

            ZCard(cornerRadius: HMetrics.cardRadius) {
                ZToggle(isOn: $always) {
                    VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                        Text(verbatim: "始终应用").zType(.body).foregroundStyle(ZTokens.Colors.screenT1)
                        Text(verbatim: "关闭时仅更改本次连接").zType(.caption).foregroundStyle(ZTokens.Colors.screenT3)
                    }
                }
            }
            .padding(.top, ZTokens.Space.n5)

            Text(verbatim: "此版本暂不支持为单个域名更改路由。")
                .zType(.caption)
                .foregroundStyle(ZTokens.Colors.screenT3)
                .padding(.horizontal, ZTokens.Space.n1)
                .padding(.top, ZTokens.Space.n3)
        }
        .disabled(true)
        .opacity(0.55)
        .accessibilityElement(children: .contain)
        .accessibilityHint(Text(verbatim: "暂不可用"))
    }
}

#Preview {
    HPreview(model: .preview()) { TraceOverrideSection(currentSceneId: "ai").padding() }
}
