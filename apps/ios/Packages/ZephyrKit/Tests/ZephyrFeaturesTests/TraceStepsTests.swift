// 连接轨迹步骤（规则 → 场景 → 节点 → 出口）单测。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

final class TraceStepsTests: XCTestCase {
    let now: Int64 = 1_793_929_260_000
    let usFixed = NodeSummary(id: 1, name: "US-Fixed-01", region: "US", tag: "原生", protocol: "VLESS", latencyMs: 188)
    let sg = NodeSummary(id: 2, name: "新加坡 02", region: "SG", protocol: "Hy2", latencyMs: 74)
    let layers = [RuleLayer(index: 1, kind: .override, name: "Zephyr 覆写", count: 3, note: ""),
                  RuleLayer(index: 3, kind: .subscription, name: "Nebula Cloud", count: 41, note: "")]

    private var ai: ZephyrKit.Scene {
        ZephyrKit.Scene(id: "ai", kind: .ai, name: "AI", available: 9, selected: sg, exitIp: "198.51.100.7", source: .auto,
                        testedAt: now - 2 * 3_600_000, exceptions: [SceneException(app: "Claude", node: usFixed)])
    }

    private func trace(_ policy: String, layer: Int32? = 3, rule: String = "DOMAIN-SUFFIX,claude.ai", scene: ZephyrKit.Scene? = nil,
                       exitIp: String? = nil) -> RuleTrace {
        RuleTrace(input: "claude.ai", isIp: false, layerIndex: layer, rule: rule, ruleNo: 41, policy: policy, scene: scene,
                  exitIp: exitIp, tookMicros: 12)
    }

    private func host(node: String) -> RecentHost {
        RecentHost(host: "claude.ai", scene: "ai", node: node, connections: 17, totalBytes: 2_100_000, lastSeenAt: now - 3000, connectionIds: [])
    }

    func testRuleText() {
        XCTAssertEqual(TraceSteps.ruleText("DOMAIN-SUFFIX,claude.ai"), "DOMAIN-SUFFIX, claude.ai")
        XCTAssertEqual(TraceSteps.ruleText("MATCH"), "MATCH")
        XCTAssertEqual(TraceSteps.ruleText("IP-CIDR, 10.0.0.0/8 ,no-resolve"), "IP-CIDR, 10.0.0.0/8, no-resolve")
    }

    func testPrototypeClaudeTraceUsesExceptionNode() {
        let s = TraceSteps.build(trace: trace("ai", scene: ai, exitIp: "198.51.100.7"), layers: layers, scenes: [ai],
                                 latest: host(node: "US-Fixed-01"), now: now)
        XCTAssertEqual(s.map(\.label), ["规则", "场景", "节点", "出口"])
        XCTAssertEqual(s[0].value, "DOMAIN-SUFFIX, claude.ai")
        XCTAssertEqual(s[0].detail, "来自 Nebula Cloud")
        XCTAssertTrue(s[0].monospaced)
        XCTAssertEqual(s[1].value, "AI")
        XCTAssertEqual(s[1].detail, "Zephyr 优选")
        XCTAssertEqual(s[2].value, "US-Fixed-01")
        XCTAssertEqual(s[2].regionCode, "US")
        XCTAssertEqual(s[2].detail, "Claude 例外 · 固定")
        // 例外节点的出口 IP 不是场景出口：不冒用 198.51.100.7
        XCTAssertEqual(s[3].value, "未检测")
        XCTAssertFalse(s[3].monospaced)
        XCTAssertEqual(s[3].marker, .success)
        XCTAssertEqual(s[3].detail, HRegionName.name("US"))
    }

    func testSceneLookupByPolicyAndSelectedNode() {
        let s = TraceSteps.build(trace: trace("ai"), layers: layers, scenes: [ai], latest: nil, now: now)
        XCTAssertEqual(s[2].value, "新加坡 02")
        XCTAssertEqual(s[2].detail, "74 ms · Hy2")
        XCTAssertEqual(s[3].value, "198.51.100.7")
        XCTAssertTrue(s[3].monospaced)
        XCTAssertEqual(s[3].detail, "\(HRegionName.name("SG")) · 2 小时前检测")
    }

    func testDirectRejectAndMatch() {
        let d = TraceSteps.build(trace: trace("DIRECT", layer: nil, rule: "MATCH"), layers: layers, scenes: [ai], latest: nil, now: now)
        XCTAssertEqual(d.map(\.label), ["规则", "出口"])
        XCTAssertEqual(d[0].detail, "其余流量")
        XCTAssertEqual(d[1].value, "直连")

        let r = TraceSteps.build(trace: trace("REJECT", layer: 1), layers: layers, scenes: [ai], latest: nil, now: now)
        XCTAssertEqual(r.map(\.label), ["规则", "结果"])
        XCTAssertEqual(r[0].detail, "来自 Zephyr 覆写")
        XCTAssertEqual(r[1].marker, .danger)
    }

    func testUnknownPolicyAndUnknownLayer() {
        let s = TraceSteps.build(trace: trace("Proxy", layer: 7), layers: layers, scenes: [ai], latest: nil, now: now)
        XCTAssertEqual(s[0].detail, "来自 第 7 层")
        XCTAssertEqual(s.map(\.label), ["规则", "策略"])
        XCTAssertEqual(s[1].value, "Proxy")
    }
}
