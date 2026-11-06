// RulesModel — 规则页模型：统计（ruleStats）+ 即时测试（testRule，每次输入取消上一次）。

import Observation
import SwiftUI
import ZephyrKit

@MainActor
@Observable
final class RulesModel {
    /// 一条命中链步骤（原型 .chain .st）。
    struct Step: Identifiable, Equatable {
        enum Value: Equatable {
            case text(String)
            case mono(String)
            case region(code: String, name: String)
        }
        var id: Int
        var label: String
        var value: Value
        var trailing: String?
    }

    @ObservationIgnored let engine: any ZephyrEngine
    var input: String
    private(set) var stats: RuleStats?
    private(set) var trace: RuleTrace?
    private(set) var invalid = false
    @ObservationIgnored private var testTask: Task<Void, Never>?

    /// 原型默认预填 chat.openai.com。
    static let defaultInput = "chat.openai.com"

    init(engine: any ZephyrEngine, query: String?) {
        self.engine = engine
        self.input = query ?? Self.defaultInput
    }

    func start() async {
        stats = await engine.ruleStats()
        runTest()
    }

    func runTest() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        testTask?.cancel()
        guard !q.isEmpty else { trace = nil; invalid = false; return }
        testTask = Task { [weak self] in
            guard let self else { return }
            do {
                let t = try await self.engine.testRule(input: q)
                guard !Task.isCancelled else { return }
                self.trace = t
                self.invalid = false
            } catch {
                guard !Task.isCancelled else { return }
                self.trace = nil
                self.invalid = true
            }
        }
    }

    // MARK: 派生

    /// “7 层 · 已编译 · 磁盘占用 1.9 GB”
    var subtitle: String? {
        guard let s = stats else { return nil }
        return "\(s.layers.count) 层 · \(s.compiled ? "已编译" : "编译中") · 磁盘占用 \(ZFormat.bytes(s.diskBytes))"
    }

    /// 命中的匹配顺序行（0 基层下标；layers.count = 第 8 行“其余流量”）；无测试时 nil。
    var hitRow: Int? {
        guard let t = trace, let s = stats else { return nil }
        if let li = t.layerIndex { return s.layers.firstIndex { $0.index == li } }
        return s.layers.count
    }

    /// 命中链：请求 → 第 n 层 · 规则 #序号 → 场景/出口 IP 或 已拦截/直连。
    var steps: [Step] {
        guard let t = trace else { return [] }
        var out: [Step] = [Step(id: 0, label: "请求", value: .mono(t.input))]
        if let li = t.layerIndex, let layer = stats?.layers.first(where: { $0.index == li }) {
            out.append(Step(id: 1, label: "第 \(li + 1) 层 · \(layer.name)", value: .mono(t.rule),
                            trailing: t.ruleNo.map { "#\(ZFormat.count($0))" }))
        } else {
            let n = (stats?.layers.count ?? 7) + 1
            out.append(Step(id: 1, label: "第 \(n) 层 · 其余流量", value: .mono(t.rule)))
        }
        switch t.policy {
        case "DIRECT":
            out.append(Step(id: 2, label: "出口", value: .text("直连")))
        case "REJECT":
            out.append(Step(id: 2, label: "结果", value: .text("已拦截")))
        default:
            if let scene = t.scene {
                out.append(Step(id: 2, label: "场景 · \(scene.name)",
                                value: .region(code: scene.selected.region, name: scene.selected.name)))
            } else {
                out.append(Step(id: 2, label: "场景", value: .text(t.policy)))
            }
            if let ip = t.exitIp ?? t.scene?.exitIp {
                out.append(Step(id: 3, label: "出口 IP", value: .mono(ip)))
            }
        }
        return out
    }

    /// “用时 0.12 ms”
    var tookText: String? {
        trace.map { String(format: "用时 %.2f ms", Double($0.tookMicros) / 1000) }
    }
}
