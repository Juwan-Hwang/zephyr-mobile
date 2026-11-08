// 连接轨迹（原型 09，截图 trace.png）的步骤：规则 → 场景 → 节点 → 出口。
//
// 契约 §13 的 connectionTrace(host:) 尚未进入 Swift 协议（见 NOTES-H.md），这里用已有数据拼出：
//   规则 = engine.testRule(input: host)（命中层名来自 ruleStats().layers）
//   场景 = RuleTrace.scene，或按 policy（场景 id）在当前 scenes 里找
//   节点 = 该域名最近一条活动连接的 node（含例外），否则场景当前节点
//   出口 = RuleTrace.exitIp ?? Scene.exitIp，地区取节点地区
// 纯 Swift（只依赖 ZephyrKit），便于单测（Tests/ZephyrFeaturesTests/TraceStepsTests.swift）。

import Foundation
import ZephyrKit

struct TraceStep: Hashable, Identifiable, Sendable {
    enum Marker: Hashable, Sendable { case hollow, success, danger }

    var label: String
    var value: String
    var detail: String?
    var regionCode: String?
    var monospaced = false
    var marker: Marker = .hollow
    var id: String { label }
}

enum TraceSteps {
    static let direct = "DIRECT"
    static let reject = "REJECT"

    /// - Parameters:
    ///   - trace: testRule(input: host) 的结果。
    ///   - layers: ruleStats().layers（取命中层名称作"来自 …"）。
    ///   - scenes: 当前场景列表（trace.scene 为空时按 policy 查）。
    ///   - latest: 该域名最近一条活动连接（拿实际出口节点名，含例外）。
    ///   - now: 当前时间（毫秒），出口"x 小时前检测"用。
    static func build(trace: RuleTrace, layers: [RuleLayer], scenes: [ZephyrKit.Scene],
                      latest: RecentHost?, now: Int64) -> [TraceStep] {
        var steps = [ruleStep(trace, layers: layers)]
        let policy = trace.policy.uppercased()
        if policy == reject {
            steps.append(TraceStep(label: ZL.tr("结果"), value: ZL.tr("已拦截"), detail: ZL.tr("请求在本机被丢弃，不会发出"), marker: .danger))
            return steps
        }
        if policy == direct {
            steps.append(TraceStep(label: ZL.tr("出口"), value: ZL.tr("直连"), detail: ZL.tr("不经过代理，使用本机网络"), marker: .success))
            return steps
        }
        guard let scene = trace.scene ?? scenes.first(where: { $0.id == trace.policy }) else {
            // 策略组 / 未知策略：只显示策略名。
            steps.append(TraceStep(label: ZL.tr("策略"), value: trace.policy, marker: .success))
            return steps
        }
        steps.append(TraceStep(label: ZL.tr("场景"), value: scene.name, detail: sourceText(scene.source)))

        let (node, exception) = resolveNode(scene: scene, latest: latest)
        var nodeDetail: String?
        if let exception {
            nodeDetail = ZL.s("%@ 例外 · 固定", exception.app)
        } else if let node {
            nodeDetail = [node.latencyMs.map { ZFormat.latency($0) }, node.tag, node.protocol.isEmpty ? nil : node.protocol]
                .compactMap { $0 }.joined(separator: " · ")
        }
        let nodeName = node?.name ?? latest?.node ?? scene.selected.name
        steps.append(TraceStep(label: ZL.tr("节点"), value: nodeName, detail: nodeDetail?.isEmpty == true ? nil : nodeDetail,
                               regionCode: node?.region))

        let ip = exception == nil ? (trace.exitIp ?? scene.exitIp) : nil
        var exitDetail: [String] = []
        if let r = node?.region { exitDetail.append(HRegionName.name(r)) }
        if exception == nil, let t = scene.testedAt { exitDetail.append(ZL.s("%@检测", ZFormat.relative(t, now: now))) }
        steps.append(TraceStep(label: ZL.tr("出口"), value: ip ?? ZL.tr("未检测"), detail: exitDetail.isEmpty ? nil : exitDetail.joined(separator: " · "),
                               monospaced: ip != nil, marker: .success))
        return steps
    }

    /// "DOMAIN-SUFFIX,claude.ai" → "DOMAIN-SUFFIX, claude.ai"（原型排版）。
    static func ruleText(_ rule: String) -> String {
        rule.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ", ")
    }

    static func sourceText(_ s: SceneSource) -> String {
        switch s {
        case .auto: ZL.tr("Zephyr 优选")
        case .manual: ZL.tr("手动选择")
        case .subscriptionGroup: ZL.tr("订阅分组")
        }
    }

    private static func ruleStep(_ t: RuleTrace, layers: [RuleLayer]) -> TraceStep {
        let detail: String
        if let i = t.layerIndex {
            let name = layers.first { $0.index == i }?.name ?? ZL.f("第 %lld 层", Int64(i))
            detail = ZL.s("来自 %@", name)
        } else {
            detail = ZL.tr("其余流量")
        }
        return TraceStep(label: ZL.tr("规则"), value: ruleText(t.rule), detail: detail, monospaced: true)
    }

    /// 实际节点：最近连接的节点名若命中场景例外 → 例外节点；命中当前节点 → 当前节点；否则只有名字。
    private static func resolveNode(scene: ZephyrKit.Scene, latest: RecentHost?) -> (NodeSummary?, SceneException?) {
        guard let name = latest?.node, name != direct else { return (scene.selected, nil) }
        if let ex = scene.exceptions.first(where: { $0.node.name == name }) { return (ex.node, ex) }
        if scene.selected.name == name { return (scene.selected, nil) }
        return (nil, nil)
    }
}
