// 轨迹页底部"本次连接"（原型 09 `#routeSeg` + "始终应用"开关）：
//   本次连接  [不变 | 直连 | 视频 | 其他]
//   ┌ 始终应用                 ◯ ┐
//   └ 关闭时仅更改本次连接       ┘
//
// 选中即 overrideHost(host, target, sceneId, persistent: 始终应用)（契约 §13）；成功后给可撤销吐司（撤销 = .unchanged）。
// 打开时用 engine.hostOverride(host:) 回填当前覆写（分段与“始终应用”）；没有覆写从“不变”开始。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct TraceOverrideSection: View {
    let host: String
    /// 当前命中的场景 id（不在分段里重复出现）；直连 / 拦截时为 "DIRECT" / "REJECT"。
    let currentSceneId: String?
    @Environment(AppModel.self) private var model
    @State private var always = false
    @State private var selection: Target = .unchanged
    @State private var busy = false
    /// 用户已动过分段或开关：回填不再覆盖。
    @State private var touched = false

    fileprivate enum Target: Hashable { case unchanged, direct, scene(String) }

    /// 原型只有 4 段（不变 / 直连 / 两个场景）；再多会挤得点不准。
    private static let maxScenes = 2

    private var segments: [ZSegment<Target>] {
        var out = [ZSegment(Target.unchanged, verbatim: "不变")]
        if currentSceneId?.uppercased() != "DIRECT" { out.append(ZSegment(.direct, verbatim: "直连")) }
        for s in model.scenes.filter({ $0.id != currentSceneId }).prefix(Self.maxScenes) {
            out.append(ZSegment(.scene(s.id), verbatim: s.name))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("本次连接")
                .zType(.caption)
                .foregroundStyle(ZColor.t3)
                .padding(.horizontal, ZTokens.Space.n1)
                .padding(.top, ZTokens.Space.n6)
                .padding(.bottom, ZTokens.Space.n3)
                .accessibilityAddTraits(.isHeader)
            ZSegmented(segments,
                       selection: Binding(get: { selection }, set: { choose($0) }),
                       label: "本次连接的路由")
                .disabled(busy)

            ZCard(cornerRadius: HMetrics.cardRadius) {
                ZToggle(isOn: Binding(get: { always }, set: { touched = true; always = $0; if selection != .unchanged { choose(selection, force: true) } })) {
                    VStack(alignment: .leading, spacing: ZTokens.Space.n1 / 2) {
                        Text("始终应用").zType(.body).foregroundStyle(ZTokens.Colors.screenT1)
                        Text("关闭时仅更改本次连接").zType(.caption).foregroundStyle(ZColor.t3)
                    }
                }
            }
            .padding(.top, ZTokens.Space.n5)
        }
        .accessibilityElement(children: .contain)
        .task(id: host) { await backfill() }
    }

    /// 回填当前覆写；用户已经开始操作则不覆盖。
    private func backfill() async {
        guard let o = await model.engine.hostOverride(host: host), !touched, !busy else { return }
        let target: Target
        switch o.target {
        case .unchanged: return
        case .direct: target = .direct
        case .scene:
            guard let id = o.sceneId else { return }
            target = .scene(id)
        }
        // 只回填分段里实际有的选项，避免选中一个看不见的段。
        guard segments.contains(where: { $0.value == target }) else { return }
        selection = target
        always = o.persistent
    }

    private func choose(_ new: Target, force: Bool = false) {
        guard new != selection || force, !busy else { return }
        touched = true
        let previous = selection
        selection = new
        busy = true
        Task {
            let target: TraceTarget
            var sceneId: String?
            switch new {
            case .unchanged: target = .unchanged
            case .direct: target = .direct
            case .scene(let id): target = .scene; sceneId = id
            }
            let ok = await model.overrideHost(host, target: target, sceneId: sceneId, persistent: always)
            if !ok { selection = previous }
            busy = false
        }
    }
}

#Preview {
    HPreview(model: .preview()) { TraceOverrideSection(host: "claude.ai", currentSceneId: "ai").padding() }
}
