// 契约 §15.h 指令“视频只用 4K 节点”：CommandFilterCard 的文案 / 出口变化决策、FilterPreview.canApply，
// 以及 CommandModel → AppModel.applySceneNodeFilter 的行为（不自动切换 §14.y、已开启可取消、撤销恢复）。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class CommandFilterTests: XCTestCase {

    // MARK: 辅助

    private func until(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private let jp4K = NodeSummary(id: 9_001, name: "东京 4K 01", region: "JP", protocol: "VLESS", latencyMs: 61, uhd: true)
    private let exitHKtoJP = ExitChange(sceneId: "video", fromRegion: "HK", fromIp: "203.0.113.24",
                                        toRegion: "JP", toIp: "203.0.113.61", affectedApps: ["Netflix", "YouTube"])

    private func filter(active: Bool = false, _ r: NodeFilterPreview) -> CommandModel.FilterPreview {
        CommandModel.FilterPreview(sceneId: "video", sceneName: "视频", active: active, result: r)
    }

    private func card(_ f: CommandModel.FilterPreview) -> CommandFilterCard {
        CommandFilterCard(preview: f, isApplying: false, onApply: {})
    }

    /// 启动挂 stub 引擎的 AppModel，等场景落地。
    private func start(_ engine: FilterStubEngine) async -> AppModel {
        let model = AppModel(engine: engine, now: { MockClock.frozen941.now() })
        model.start()
        _ = await until { model.scene(id: "video") != nil }
        return model
    }

    /// 输入指令，等 4K 过滤预览出来。
    private func command(_ model: AppModel, _ text: String = "视频只用 4K 节点") async -> CommandModel {
        let cmd = CommandModel(app: model)
        cmd.input = text
        _ = await until { cmd.filterPreview != nil }
        return cmd
    }

    /// 视频场景里一个不是当前节点、Mock 能解析的候选（当作“建议的 4K 节点”）。
    private func otherVideoNode(_ engine: FilterStubEngine, model: AppModel) async throws -> NodeSummary {
        let current = try XCTUnwrap(model.scene(id: "video")?.selected.id)
        let list = try await engine.base.sceneCandidates(sceneId: "video", region: nil)
        return try XCTUnwrap(list.first { $0.id != current && ($0.latencyMs ?? -1) >= 0 })
    }

    // MARK: 卡片决策（纯值）

    func testPoolMatchingZeroDisablesApply() {
        let f = filter(NodeFilterPreview(matching: 0, total: 22, poolMatching: 0, currentKept: false))
        XCTAssertFalse(f.canApply, "当前地区没有 4K 节点时禁用应用")
        XCTAssertEqual(card(f).summary, "没有支持 4K 的节点")
        XCTAssertNil(card(f).exitChange)
    }

    func testUntestedUHDNodesPromptRetest() {
        let f = filter(NodeFilterPreview(matching: 0, total: 22, poolMatching: 6, currentKept: false))
        XCTAssertTrue(f.canApply, "池里有 4K 节点即可开启")
        XCTAssertEqual(card(f).summary, "4K 节点还没有测速，在场景中重新检测后可用。")
        XCTAssertNil(card(f).exitChange, "没有已测候选时不展示出口变化")
    }

    func testCurrentKeptSummaryHasNoExitChange() {
        let f = filter(NodeFilterPreview(matching: 14, total: 22, poolMatching: 14, currentKept: true))
        XCTAssertEqual(card(f).summary, "22 个中 14 个支持 4K，当前节点保持不变。")
        XCTAssertNil(card(f).exitChange)
    }

    func testNotKeptShowsExitIPChange() {
        let f = filter(NodeFilterPreview(matching: 14, total: 22, poolMatching: 14, currentKept: false,
                                         suggested: jp4K, change: exitHKtoJP))
        XCTAssertEqual(card(f).summary, "22 个中 14 个支持 4K，将使用东京 4K 01。")
        XCTAssertEqual(card(f).exitChange, exitHKtoJP, "当前节点不满足时卡片展示出口 IP 变化")
    }

    func testNotKeptWithIdenticalExitHidesChange() {
        let same = ExitChange(sceneId: "video", fromRegion: "HK", fromIp: "203.0.113.24", toRegion: "HK", toIp: "203.0.113.24")
        let f = filter(NodeFilterPreview(matching: 3, total: 22, poolMatching: 3, currentKept: false, suggested: jp4K, change: same))
        XCTAssertNil(card(f).exitChange, "出口地区与 IP 都不变时不提示")
    }

    func testActiveFilterOffersCancelEvenWithoutUHDNodes() {
        let f = filter(active: true, NodeFilterPreview(matching: 0, total: 22, poolMatching: 0, currentKept: false,
                                                       suggested: jp4K, change: exitHKtoJP))
        XCTAssertTrue(f.canApply, "已开启时总能取消")
        XCTAssertEqual(card(f).summary, "已开启。取消后恢复使用全部节点，当前节点保持不变。")
        XCTAssertNil(card(f).exitChange, "取消不换节点")
    }

    // MARK: CommandModel / AppModel 行为（stub 引擎）

    func testPreviewDoesNotSwitchBeforeApply() async throws {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 0, total: 22, poolMatching: 0, currentKept: true))
        let model = await start(engine)
        let suggested = try await otherVideoNode(engine, model: model)
        let change = try await engine.previewSceneChange(sceneId: "video", nodeId: suggested.id)
        engine.preview = NodeFilterPreview(matching: 14, total: 22, poolMatching: 14, currentKept: false,
                                           suggested: suggested, change: change)
        let before = try XCTUnwrap(model.scene(id: "video"))

        let cmd = await command(model)
        let f = try XCTUnwrap(cmd.filterPreview)
        XCTAssertNil(cmd.preview, "4K 预览取代 switch_node 主预览")
        XCTAssertTrue(cmd.hasPrimary)
        XCTAssertFalse(f.active)
        XCTAssertNotNil(card(f).exitChange, "未点应用前先展示出口 IP 变化")

        try? await Task.sleep(nanoseconds: 200_000_000)
        let now = try XCTUnwrap(model.scene(id: "video"))
        XCTAssertEqual(now.selected.id, before.selected.id, "未点应用前当前节点不变（§14.y 不自动切换）")
        XCTAssertNil(now.nodeFilter)
        XCTAssertTrue(engine.setCalls.isEmpty, "预览不写过滤")
    }

    func testApplySwitchesToSuggestedAndUndoRestores() async throws {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 0, total: 22, poolMatching: 0, currentKept: true))
        let model = await start(engine)
        let suggested = try await otherVideoNode(engine, model: model)
        let change = try await engine.previewSceneChange(sceneId: "video", nodeId: suggested.id)
        engine.preview = NodeFilterPreview(matching: 14, total: 22, poolMatching: 14, currentKept: false,
                                           suggested: suggested, change: change)
        let original = try XCTUnwrap(model.scene(id: "video")?.selected.id)

        let cmd = await command(model)
        let applied = await cmd.applyPreview()
        XCTAssertTrue(applied)
        let on = await until { model.scene(id: "video")?.nodeFilter == .uhd && model.scene(id: "video")?.selected.id == suggested.id }
        XCTAssertTrue(on, "点应用后开启过滤并换到 suggested")
        XCTAssertEqual(engine.setCalls, [.uhd])
        XCTAssertNotNil(model.toast?.actionTitle, "成功吐司可撤销")

        model.toast?.action?()
        let undone = await until { model.scene(id: "video")?.nodeFilter == nil && model.scene(id: "video")?.selected.id == original }
        XCTAssertTrue(undone, "撤销恢复过滤为 nil 并换回原节点")
        XCTAssertEqual(engine.setCalls, [.uhd, nil])
    }

    func testCurrentKeptApplyDoesNotSwitch() async throws {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 14, total: 22, poolMatching: 14, currentKept: true))
        let model = await start(engine)
        let original = try XCTUnwrap(model.scene(id: "video")?.selected.id)

        let cmd = await command(model)
        let applied = await cmd.applyPreview()
        XCTAssertTrue(applied)
        let on = await until { model.scene(id: "video")?.nodeFilter == .uhd }
        XCTAssertTrue(on)
        XCTAssertEqual(model.scene(id: "video")?.selected.id, original, "当前节点满足时不换节点")
        XCTAssertEqual(model.toast?.message, "视频仅使用 4K 节点")
    }

    func testPoolMatchingZeroModelCannotApply() async throws {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 0, total: 22, poolMatching: 0, currentKept: false))
        let model = await start(engine)

        let cmd = await command(model)
        let f = try XCTUnwrap(cmd.filterPreview)
        XCTAssertFalse(f.canApply)
        XCTAssertFalse(cmd.hasPrimary, "禁用时回车不可执行")
        let applied = await cmd.applyPreview()
        XCTAssertFalse(applied)
        XCTAssertTrue(engine.setCalls.isEmpty)
        XCTAssertNil(model.lastError, "禁用不走错误横幅")
    }

    func testActiveFilterCommandCancels() async throws {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 14, total: 22, poolMatching: 14, currentKept: true),
                                      active: ["video": .uhd])
        let model = await start(engine)
        _ = await until { model.scene(id: "video")?.nodeFilter == .uhd }
        let original = try XCTUnwrap(model.scene(id: "video")?.selected.id)

        let cmd = await command(model)
        let f = try XCTUnwrap(cmd.filterPreview)
        XCTAssertTrue(f.active, "已开启时卡片改为取消")
        XCTAssertTrue(f.canApply)
        let applied = await cmd.applyPreview()
        XCTAssertTrue(applied)
        let off = await until { model.scene(id: "video")?.nodeFilter == nil }
        XCTAssertTrue(off)
        XCTAssertEqual(engine.setCalls, [nil])
        XCTAssertEqual(model.scene(id: "video")?.selected.id, original, "取消不换节点")
        XCTAssertEqual(model.toast?.message, "视频已取消仅 4K 节点")
    }

    func testSetThenUndoRestoresNil() async throws {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 14, total: 22, poolMatching: 14, currentKept: true))
        let model = await start(engine)

        let ok = await model.applySceneNodeFilter(sceneId: "video", filter: .uhd)
        XCTAssertTrue(ok)
        let on = await until { model.scene(id: "video")?.nodeFilter == .uhd }
        XCTAssertTrue(on)

        model.toast?.action?()
        let restored = await until { model.scene(id: "video")?.nodeFilter == nil }
        XCTAssertTrue(restored, "撤销把过滤恢复为 nil")
        XCTAssertEqual(engine.setCalls, [.uhd, nil])
        XCTAssertNil(model.lastError)
    }

    func testSetFailureReportsAndKeepsScene() async throws {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 0, total: 22, poolMatching: 0, currentKept: false))
        let model = await start(engine)

        let ok = await model.applySceneNodeFilter(sceneId: "video", filter: .uhd)
        XCTAssertFalse(ok)
        XCTAssertEqual(model.lastError?.code, .ruleInputInvalid, "失败走顶部横幅")
        XCTAssertNil(model.toast)
        XCTAssertNil(model.scene(id: "video")?.nodeFilter)
    }
}
