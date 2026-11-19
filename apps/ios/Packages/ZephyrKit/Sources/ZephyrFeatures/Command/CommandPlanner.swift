// 契约 §16.d 指令语义（以原型 render() / apply() 为准，index.html 1020–1061）：解析结果 → 一张预览卡，
// 用户点“应用”才执行，执行后出 5 s 撤销吐司。
//
//   "Gemini 走日本"  AI / 视频范围的单个服务 + 地区 → 只钉该服务的例外 setSceneException（场景 selected 不变）
//   "视频走日本"     场景词 + 地区                 → 整场景 applySceneChange
//   "GitHub 直连"    “其他”范围服务 + 直连         → 只让该域名直连 overrideHost(host, direct, nil, persistent: true)
//   "视频只用 4K 节点"                             → §15.h（CommandModel.FilterPreview，不在这里）
//
// 有意收窄 / 照原型不出卡片：AI / 视频服务 + 直连（一个应用多个域名，单域名覆写会误导）；场景词 + 直连；
// “其他”范围服务 + 地区。

import Foundation
import ZephyrKit

enum CommandPlan: Equatable {
    /// "Gemini 使用日本节点"：appId 非 nil = 单服务例外，nil = 整场景（场景词）。
    struct Exit: Equatable {
        /// 卡片与吐司里的主语：服务名（Gemini）或场景显示名（视频）。
        var who: String
        var sceneId: String
        var appId: String?
        var regionCode: String
        var available: Int
        var node: NodeSummary
        /// nil = 出口已在该地区（原型 `same`），不显示出口 IP 行。
        var exit: ExitChange?
        /// 该服务原有例外且不是同一节点："Claude 将不再使用固定出口 US-Fixed-01。"
        var releasesPin: String?
        /// 撤销用：例外 = 原例外节点（nil = 原来没有例外）；整场景 = 原 selected。
        var previous: NodeSummary?

        var isException: Bool { appId != nil }
    }

    /// "GitHub 直连"。
    struct Direct: Equatable {
        var who: String
        var host: String
        /// “其他”场景当前出口（出口 IP 行左侧）；未知为 nil。
        var fromRegion: String?
        var fromIp: String?
    }

    case exit(Exit)
    /// "AI 场景中没有英国节点。"，按钮禁用“无可用节点”。
    case noNodes(who: String, sceneName: String, regionCode: String)
    case direct(Direct)

    var canApply: Bool {
        if case .noNodes = self { return false }
        return true
    }
}

@MainActor
enum CommandPlanner {
    /// 解析结果 → 预览卡；nil = 只显示解析卡片（及引擎的其余结果行）。4K 操作由 FilterPreview 处理，这里返回 nil。
    static func plan(_ p: CommandParse, scenes: [ZephyrKit.Scene], engine: any ZephyrEngine) async -> CommandPlan? {
        guard let sceneId = p.sceneId else { return nil }
        if p.wantsUHD { return nil }
        let scene = scenes.first { $0.id == sceneId }

        if p.wantsDirect {
            // 只开放“其他”范围的服务（有登记域名）；AI / 视频服务、场景词 + 直连 v1 不出卡片。
            guard let svc = p.serviceName, let host = p.host else { return nil }
            let other = scene ?? scenes.first { $0.kind == .other }
            let region = other.flatMap { $0.selected.region.isEmpty ? nil : $0.selected.region }
            return .direct(.init(who: svc, host: host, fromRegion: region, fromIp: other?.exitIp))
        }

        guard let region = p.regionCode, let scene, sceneId != "other" else { return nil }
        let single = !p.isSceneWord
        // 单服务例外只给应用目录里的服务（appId）；场景词走整场景。
        if single && p.appId == nil { return nil }
        let who = single ? (p.serviceName ?? scene.displayName) : scene.displayName

        let pool = (try? await engine.sceneCandidates(sceneId: scene.id, region: region)) ?? []
        guard let best = pool.first else {
            return .noNodes(who: who, sceneName: scene.displayName, regionCode: region)
        }

        let pin = single ? exception(in: scene, appId: p.appId, service: p.serviceName) : nil
        let currentRegion = pin?.node.region ?? scene.selected.region
        var exit: ExitChange?
        if currentRegion.uppercased() != region.uppercased() {
            exit = try? await engine.previewSceneChange(sceneId: scene.id, nodeId: best.id)
            // 原有例外：出口是例外节点，不是场景出口；IP 未知时只显示地区。
            if let pin, exit != nil { exit?.fromRegion = pin.node.region; exit?.fromIp = nil }
        }
        return .exit(.init(
            who: who, sceneId: scene.id, appId: single ? p.appId : nil, regionCode: region,
            available: pool.count, node: best, exit: exit,
            releasesPin: pin.flatMap { $0.node.id == best.id ? nil : $0.node.name },
            previous: single ? pin?.node : scene.selected))
    }

    /// 该服务在场景里的现有例外：先按 appId，旧数据没有 appId 时按显示名（核心给目录名 ChatGPT，指令显示 GPT）。
    static func exception(in scene: ZephyrKit.Scene, appId: String?, service: String?) -> SceneException? {
        if let appId, let e = scene.exceptions.first(where: { $0.appId == appId }) { return e }
        let names = Set([service, appId.flatMap { catalogNames[$0] }].compactMap { $0?.lowercased() })
        return scene.exceptions.first { $0.appId == nil && names.contains($0.app.lowercased()) }
    }

    /// 契约 §10 应用目录显示名（核心 SceneExceptionView.app）。
    static let catalogNames: [String: String] = ["chatgpt": "ChatGPT", "claude": "Claude", "gemini": "Gemini",
                                                 "netflix": "Netflix", "youtube": "YouTube", "disney": "Disney+"]
}
