// 连接轨迹（原型 09，截图 trace.png）：
//   claude.ai
//   3 秒前 · 17 个连接 · 2.1 MB
//   ○ 规则  DOMAIN-SUFFIX, claude.ai   来自 Nebula Cloud
//   ○ 场景  AI                         Zephyr 优选
//   ○ 节点  US-Fixed-01                Claude 例外 · 固定
//   ● 出口  203.0.113.24               美国 · 2 小时前检测
//   本次连接 [不变|直连|视频|其他]  始终应用（TraceOverrideSection，overrideHost）
//
// 数据：engine.hostTrace(host:)（mihomo 实测，隧道连接时）+ engine.testRule(input: host) + ruleStats().layers + 当前 scenes
//       + 该域名最近一条活动连接（TraceSteps）。
// 动效：步骤逐个从左淡入（80ms 起、每步 +60ms，原型 playTrace）；竖线上一段光沿链路流动（原型 `.rail i`）。
// Reduce Motion：直接显示、光点静止隐藏。

import SwiftUI
import ZephyrDesign
import ZephyrKit

@MainActor
struct TraceView: View {
    let host: String
    /// 该域名在"刚才"里的聚合（无活动连接时为 nil）。
    let recent: RecentHost?
    /// 从列表进入时显示"‹ 刚才"返回；深链直达时为 nil。
    let onBack: (@MainActor () -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var trace: RuleTrace?
    @State private var live: HostTraceInfo?
    @State private var layers: [RuleLayer] = []
    @State private var failure: ZephyrError?
    @State private var shown = false

    private var steps: [TraceStep] {
        guard let trace else { return [] }
        return TraceSteps.build(trace: trace, layers: layers, scenes: model.scenes, latest: recent, now: model.now(), live: live)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onBack { backButton(onBack) }
            Text(verbatim: host)
                .foregroundStyle(ZTokens.Colors.screenT1)
                .zDisplay(.small, weight: .light)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .padding(.top, onBack == nil ? ZTokens.Space.n6 : ZTokens.Space.n3)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: lede)
                .zType(.footnote)
                .foregroundStyle(ZColor.t3)
                .padding(.top, ZTokens.Space.n2)

            chain
                .padding(.top, ZTokens.Space.n6 + ZTokens.Space.n1 / 2)

            if let trace, failure == nil {
                TraceOverrideSection(host: host, currentSceneId: live.map { $0.scene ?? $0.node } ?? trace.scene?.id ?? trace.policy)
            }
        }
        .padding(.horizontal, HMetrics.homeInset)
        .padding(.bottom, ZTokens.Space.n8)
        .task(id: host) { await load() }
    }

    // MARK: 区块

    private func backButton(_ action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: ZTokens.Space.n1) {
                Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
                Text("刚才")
            }
            .zType(.body)
            .foregroundStyle(ZAccentStyle())
            .frame(minHeight: ZTokens.Layout.touchMinIos)
            .contentShape(Rectangle())
        }
        .buttonStyle(ZPressStyle(haptic: .none))
        .accessibilityLabel(Text("返回刚才"))
    }

    @ViewBuilder
    private var chain: some View {
        if let failure {
            Text(verbatim: failure.userMessage)
                .zType(.footnote)
                .foregroundStyle(ZTokens.Colors.screenRed)
        } else if steps.isEmpty {
            placeholder
        } else {
            let list = steps
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                    ZChainStep(label: s.label, value: s.value, detail: s.detail, regionCode: s.regionCode,
                               monospacedValue: s.monospaced, position: .at(i, of: list.count),
                               marker: marker(s.marker), style: .regular)
                        .opacity(shown || reduceMotion ? 1 : 0)
                        .offset(x: shown || reduceMotion ? 0 : -ZTokens.Space.n2)
                        .animation(reduceMotion ? nil : ZMotion.slow.delay(0.08 + Double(i) * 0.06), value: shown)
                }
            }
            .overlay(alignment: .topLeading) {
                if !reduceMotion { TraceRailFlow().accessibilityHidden(true) }
            }
            .onAppear { shown = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("连接轨迹"))
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                ZChainStep(label: "规则", value: "DOMAIN-SUFFIX, example.com", detail: "来自 订阅",
                           position: .at(i, of: 4), style: .regular)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel(Text("正在加载连接轨迹"))
    }

    // MARK: 逻辑

    private var lede: String {
        if let l = live {
            return ZL.f("%1$@ · %2$lld 个连接 · %3$@", ZFormat.relative(l.lastSeenAt, now: model.now()) as NSString, Int64(l.connections), ZFormat.bytes(l.totalBytes) as NSString)
        }
        guard let r = recent else { return ZL.tr("暂无活动连接") }
        return ZL.f("%1$@ · %2$lld 个连接 · %3$@", ZFormat.relative(r.lastSeenAt, now: model.now()) as NSString, Int64(r.connections), ZFormat.bytes(r.totalBytes) as NSString)
    }

    private func marker(_ m: TraceStep.Marker) -> ZChainMarker {
        switch m {
        case .hollow: .hollow
        case .success: .success
        case .danger: .danger
        }
    }

    private func load() async {
        failure = nil
        let engine = model.engine
        let host = self.host
        async let stats = engine.ruleStats()
        async let measured = engine.hostTrace(host: host)
        do {
            let t = try await engine.testRule(input: host)
            layers = await stats.layers
            live = await measured
            trace = t
        } catch let e as ZephyrError {
            _ = await stats
            _ = await measured
            failure = e
        } catch {
            _ = await stats
            _ = await measured
            failure = ZephyrError(code: .internal, message: String(describing: error))
        }
    }
}

/// 轨迹竖线上流动的光（原型 `.rail i`：40pt 渐变段，1.8s 从上到下循环）。
/// 只画在竖线所在的 x（点的中心），不拦截点击。
@MainActor
private struct TraceRailFlow: View {
    private static let segment: CGFloat = 40
    private static let period: Double = 1.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                // ZMotion.page 的缓动近似：ease-in-out
                let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                let x = HMetrics.traceDot / 2
                let top = HMetrics.traceDot
                let bottom = max(top, size.height - ZTokens.Space.n6)
                let y = top - Self.segment + CGFloat(e) * (bottom - top + Self.segment)
                g.clip(to: Path(CGRect(x: 0, y: top, width: HMetrics.traceDot, height: bottom - top)))
                let rect = CGRect(x: x - HMetrics.hairline / 2, y: y, width: HMetrics.hairline, height: Self.segment)
                g.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [ZTokens.Colors.colorDownload.opacity(0), ZTokens.Colors.colorDownload,
                                      ZTokens.Colors.colorDownload.opacity(0)]),
                    startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x, y: y + Self.segment)))
            }
        }
        .frame(width: HMetrics.traceDot)
        .frame(maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

#Preview("轨迹") {
    HPreview(model: .preview()) {
        ScrollView { TraceView(host: "claude.ai", recent: nil, onBack: {}) }
    }
}

#Preview("轨迹 · 直连 · 浅色") {
    HPreview(model: .preview(), scheme: .light) {
        ScrollView { TraceView(host: "qq.com", recent: nil, onBack: nil) }
    }
}
