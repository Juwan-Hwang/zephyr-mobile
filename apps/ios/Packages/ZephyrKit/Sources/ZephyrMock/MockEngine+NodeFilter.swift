// MockEngine 契约 §15.h 场景节点过滤（“视频只用 4K 节点”）。
// 与核心同口径：4K 按名字判定（含 4K / UHD / 8K，仅 ASCII 不区分大小写）；preview 按 mock 候选算，change 复用 previewSceneChange。
// 不主动切当前节点（§14.y）；当前池里没有 4K 节点时 set 抛错、场景不变。

import Foundation
import ZephyrKit

extension MockEngine {

    /// 名字推断 4K（共享样本 contract/fixtures/uhd-names-v1.json）：仅 ASCII 不区分大小写，按 UTF-8 字节匹配。
    /// 不用 String.contains：Swift 字符串按 Unicode 规范等价比较，开尔文符号 U+212A 会等同 ASCII K。
    static func isUHD(_ name: String) -> Bool {
        let b = name.utf8.map { (0x61...0x7A).contains($0) ? $0 - 0x20 : $0 }
        return [Array("4K".utf8), Array("UHD".utf8), Array("8K".utf8)].contains { k in
            b.count >= k.count && (0...(b.count - k.count)).contains { b[$0..<($0 + k.count)].elementsEqual(k) }
        }
    }

    static func matches(_ node: NodeSummary, _ filter: SceneNodeFilter?) -> Bool {
        switch filter {
        case nil: true
        case .uhd: node.uhd || isUHD(node.name)
        }
    }

    public func previewSceneNodeFilter(sceneId: String, filter: SceneNodeFilter) async throws -> NodeFilterPreview {
        guard let scene = withState({ s in s.scenes.first { $0.id == sceneId } }), let pool = pool(sceneId) else {
            throw ZephyrError(code: .sceneNotFound, message: sceneId)
        }
        let all = try await sceneCandidates(sceneId: sceneId, region: nil, filter: nil)
        let hits = all.filter { Self.matches($0, filter) }
        let unselected = scene.selected.id == NodeId.max || scene.selected.name.isEmpty
        let kept = unselected || Self.matches(scene.selected, filter)
        let suggested = kept ? nil : hits.first { ($0.latencyMs ?? -1) >= 0 }
        let change = try await suggested.asyncMap { try await previewSceneChange(sceneId: sceneId, nodeId: $0.id) }
        return NodeFilterPreview(matching: hits.count, total: all.count,
                                 poolMatching: Int64(pool.filter { Self.matches($0, filter) }.count),
                                 currentKept: kept, suggested: suggested, change: change)
    }

    public func setSceneNodeFilter(sceneId: String, filter: SceneNodeFilter?) async throws {
        guard withState({ s in s.scenes.contains { $0.id == sceneId } }), let pool = pool(sceneId) else {
            throw ZephyrError(code: .sceneNotFound, message: sceneId)
        }
        if let filter, !pool.contains(where: { Self.matches($0, filter) }) {
            throw ZephyrError(code: .ruleInputInvalid, message: "no node matches \(filter.rawValue)")
        }
        withState { s in
            if let i = s.scenes.firstIndex(where: { $0.id == sceneId }) { s.scenes[i].nodeFilter = filter }
        }
        emitScenes()
    }
}

private extension Optional {
    func asyncMap<U>(_ body: (Wrapped) async throws -> U) async rethrows -> U? {
        guard let v = self else { return nil }
        return try await body(v)
    }
}
