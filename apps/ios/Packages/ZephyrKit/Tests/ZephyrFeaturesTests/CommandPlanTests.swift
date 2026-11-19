// 契约 §16.d 指令语义（审计 #207 U4，以原型 render() / apply() 为准）：
//   "Gemini 走日本" 只钉该服务的例外（场景 selected 与其他服务不变），撤销恢复原例外；
//   "视频走日本" 整场景换节点；"GitHub 直连" 只让 github.com 直连（persistent），撤销清除；
//   AI / 视频服务 + 直连、“其他”服务 + 地区不出预览卡；候选为空时禁用。
// 另覆盖 U24（空输入示例短语只填入）与 U25（多语言别名、示例短语在各语言下都能解析）。

import Foundation
import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class CommandPlanTests: XCTestCase {

    // MARK: 辅助

    private func until(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func start() async -> (AppModel, FilterStubEngine) {
        let engine = FilterStubEngine(preview: NodeFilterPreview(matching: 0, total: 0, poolMatching: 0, currentKept: true))
        let model = AppModel(engine: engine, now: { MockClock.frozen941.now() })
        model.start()
        _ = await until { model.scene(id: "ai") != nil && model.scene(id: "video") != nil }
        return (model, engine)
    }

    /// 输入指令，等计划结果落地（plan 为 nil 的输入等到建议回来即可）。
    private func command(_ model: AppModel, _ text: String, expectPlan: Bool = true) async -> CommandModel {
        let cmd = CommandModel(app: model)
        cmd.input = text
        if expectPlan { _ = await until { cmd.plan != nil } }
        else { try? await Task.sleep(nanoseconds: 400_000_000) }
        return cmd
    }

    private func exitPlan(_ cmd: CommandModel, file: StaticString = #filePath, line: UInt = #line) throws -> CommandPlan.Exit {
        guard case .exit(let e) = cmd.plan else {
            XCTFail("期望 exit 计划，得到 \(String(describing: cmd.plan))", file: file, line: line)
            throw XCTSkip()
        }
        return e
    }

    // MARK: 单服务例外

    func testServiceRegionPinsOnlyThatService() async throws {
        let (model, engine) = await start()
        let before = try XCTUnwrap(model.scene(id: "ai"))
        let cmd = await command(model, "Gemini 走日本")
        let e = try exitPlan(cmd)
        let jp = try await engine.sceneCandidates(sceneId: "ai", region: "JP")
        XCTAssertEqual(e.appId, "gemini")
        XCTAssertEqual(e.sceneId, "ai")
        XCTAssertEqual(e.who, "Gemini")
        XCTAssertEqual(e.node.id, jp.first?.id, "用 sceneCandidates(场景, 地区)[0]")
        XCTAssertEqual(e.available, jp.count)
        XCTAssertNotNil(e.exit, "AI 当前出口在新加坡，地区不同要显示出口 IP 行")
        XCTAssertNil(e.releasesPin)
        XCTAssertNil(e.previous, "Gemini 原来没有例外")
        XCTAssertTrue(cmd.hasPrimary)
        XCTAssertNil(cmd.preview, "识别出服务时不借用引擎 switch_node 主预览")

        let card = CommandPlanCard(plan: .exit(e), isApplying: false, onApply: {})
        XCTAssertEqual(card.notes.last, ZL.s("%1$@节点均不可用时，%2$@ 将暂停。", HRegionName.name("JP"), "Gemini"))

        let applied = await cmd.applyPreview()
        XCTAssertTrue(applied)
        _ = await until { model.scene(id: "ai")?.exceptions.contains { $0.appId == "gemini" } == true }
        let after = try XCTUnwrap(model.scene(id: "ai"))
        XCTAssertEqual(after.selected.id, before.selected.id, "场景 selected 不变")
        XCTAssertEqual(after.exceptions.first { $0.appId == "gemini" }?.node.id, e.node.id)
        XCTAssertEqual(after.exceptions.first { $0.appId == "claude" }?.node.id,
                       before.exceptions.first { $0.app == "Claude" }?.node.id, "其他服务的例外不变")
        XCTAssertEqual(model.toast?.message, ZL.s("%@ 现使用%@", "Gemini", e.node.name))

        // 撤销：原来没有例外 → 删除
        model.toast?.action?()
        _ = await until { model.scene(id: "ai")?.exceptions.contains { $0.appId == "gemini" } == false }
        XCTAssertFalse(try XCTUnwrap(model.scene(id: "ai")).exceptions.contains { $0.appId == "gemini" })
    }

    func testExistingPinIsReleasedAndRestoredOnUndo() async throws {
        let (model, _) = await start()
        let pinned = try XCTUnwrap(model.scene(id: "ai")?.exceptions.first { $0.app == "Claude" }?.node)
        let cmd = await command(model, "Claude 走日本")
        let e = try exitPlan(cmd)
        XCTAssertEqual(e.appId, "claude")
        XCTAssertEqual(e.releasesPin, pinned.name, "原有例外时提示不再使用固定出口")
        XCTAssertEqual(e.previous?.id, pinned.id)
        XCTAssertEqual(e.exit?.fromRegion, pinned.region, "出口 IP 行左侧是例外节点的地区")
        XCTAssertNil(e.exit?.fromIp)
        let card = CommandPlanCard(plan: .exit(e), isApplying: false, onApply: {})
        XCTAssertEqual(card.notes.first, ZL.s("%1$@ 将不再使用固定出口 %2$@。", "Claude", pinned.name))

        _ = await cmd.applyPreview()
        _ = await until { model.scene(id: "ai")?.exceptions.first { $0.appId == "claude" }?.node.id == e.node.id }
        XCTAssertEqual(model.scene(id: "ai")?.exceptions.first { $0.appId == "claude" }?.node.id, e.node.id)

        model.toast?.action?()
        _ = await until { model.scene(id: "ai")?.exceptions.first { $0.appId == "claude" }?.node.id == pinned.id }
        XCTAssertEqual(model.scene(id: "ai")?.exceptions.first { $0.appId == "claude" }?.node.id, pinned.id, "撤销恢复原例外节点")
    }

    func testVideoServiceExceptionAlsoPauses() async throws {
        let (model, _) = await start()
        let cmd = await command(model, "Netflix 走日本")
        let e = try exitPlan(cmd)
        XCTAssertEqual(e.appId, "netflix")
        XCTAssertEqual(e.sceneId, "video")
        let card = CommandPlanCard(plan: .exit(e), isApplying: false, onApply: {})
        // §16.d：视频服务例外不承诺“将使用场景中的其他节点”
        XCTAssertEqual(card.notes.last, ZL.s("%1$@节点均不可用时，%2$@ 将暂停。", HRegionName.name("JP"), "Netflix"))
    }

    // MARK: 整场景

    func testSceneWordSwitchesWholeScene() async throws {
        let (model, _) = await start()
        let before = try XCTUnwrap(model.scene(id: "video"))
        let cmd = await command(model, "视频走日本")
        let e = try exitPlan(cmd)
        XCTAssertNil(e.appId, "场景词 = 整场景")
        XCTAssertEqual(e.who, before.displayName)
        XCTAssertEqual(e.previous?.id, before.selected.id)
        let card = CommandPlanCard(plan: .exit(e), isApplying: false, onApply: {})
        XCTAssertEqual(card.notes.last, ZL.s("%@节点均不可用时，将使用场景中的其他节点。", HRegionName.name("JP")))

        _ = await cmd.applyPreview()
        _ = await until { model.scene(id: "video")?.selected.id == e.node.id }
        XCTAssertEqual(model.scene(id: "video")?.selected.id, e.node.id)
        XCTAssertEqual(model.toast?.message, ZL.s("%@ 现使用%@", before.displayName, e.node.name), "整场景吐司主语是场景")

        model.toast?.action?()
        _ = await until { model.scene(id: "video")?.selected.id == before.selected.id }
        XCTAssertEqual(model.scene(id: "video")?.selected.id, before.selected.id)
    }

    // MARK: 单域名直连

    func testOtherServiceDirectOverridesOneHost() async throws {
        let (model, engine) = await start()
        let cmd = await command(model, "GitHub 直连")
        guard case .direct(let d) = cmd.plan else { return XCTFail("期望 direct 计划") }
        XCTAssertEqual(d.host, "github.com")
        XCTAssertEqual(d.who, "GitHub")
        let card = CommandPlanCard(plan: .direct(d), isApplying: false, onApply: {})
        XCTAssertEqual(card.title, ZL.s("%@ 直连", "GitHub"))
        XCTAssertEqual(card.summary, ZL.s("%@ 的流量将不经过代理。", "GitHub"))
        XCTAssertEqual(card.notes, [ZL.tr("仅在 Zephyr 中生效，订阅配置保持原样。")])
        XCTAssertTrue(card.hasIPLine)

        let applied = await cmd.applyPreview()
        XCTAssertTrue(applied)
        XCTAssertEqual(engine.overrideCalls, [.init(host: "github.com", target: .direct, sceneId: nil, persistent: true)])
        XCTAssertEqual(model.toast?.message, ZL.s("%@ 现为直连", "GitHub"))

        model.toast?.action?()
        _ = await until { engine.overrideCalls.count == 2 }
        XCTAssertEqual(engine.overrideCalls.last, .init(host: "github.com", target: .unchanged, sceneId: nil, persistent: true))
    }

    func testTelegramHost() async throws {
        let (model, _) = await start()
        let cmd = await command(model, "telegram 直连")
        guard case .direct(let d) = cmd.plan else { return XCTFail("期望 direct 计划") }
        XCTAssertEqual(d.host, "telegram.org")
    }

    // MARK: 不出预览卡

    func testAIServiceDirectHasNoPreviewCard() async {
        let (model, _) = await start()
        let cmd = await command(model, "Gemini 直连", expectPlan: false)
        XCTAssertNil(cmd.plan, "AI 服务 + 直连 v1 不出预览卡")
        XCTAssertNil(cmd.preview)
        XCTAssertFalse(cmd.hasPrimary)
        XCTAssertFalse(cmd.parse.isEmpty, "仍显示解析卡片")
    }

    func testOtherServiceWithRegionHasNoPreviewCard() async {
        let (model, _) = await start()
        let cmd = await command(model, "GitHub 走日本", expectPlan: false)
        XCTAssertNil(cmd.plan)
        XCTAssertFalse(cmd.hasPrimary)
    }

    func testEmptyPoolDisablesApply() async throws {
        let (model, _) = await start()
        let cmd = await command(model, "Gemini 走德国")
        guard case .noNodes(let who, _, let code) = cmd.plan else { return XCTFail("期望 noNodes 计划") }
        XCTAssertEqual(who, "Gemini")
        XCTAssertEqual(code, "DE")
        XCTAssertFalse(cmd.hasPrimary, "无可用节点时回车不执行")
        let applied = await cmd.applyPreview()
        XCTAssertFalse(applied)
        let card = CommandPlanCard(plan: try XCTUnwrap(cmd.plan), isApplying: false, onApply: {})
        XCTAssertEqual(card.buttonTitle, ZL.tr("无可用节点"))
    }

    // MARK: U24 示例短语

    func testExamplesFillInputOnly() async {
        let (model, engine) = await start()
        let before = model.scene(id: "ai")
        let cmd = CommandModel(app: model)
        XCTAssertEqual(CommandModel.examples, ["Gemini 走日本", "GitHub 直连", "视频只用 4K 节点", "香港"])
        cmd.fill(CommandModel.examples[0])
        XCTAssertEqual(cmd.input, "Gemini 走日本")
        XCTAssertEqual(cmd.parse.serviceName, "Gemini")
        _ = await until { cmd.plan != nil }
        XCTAssertEqual(model.scene(id: "ai"), before, "点建议不直接执行")
        XCTAssertTrue(engine.overrideCalls.isEmpty)
    }

    // MARK: U25 示例短语在各语言下都能解析

    private struct Catalog: Decodable {
        struct Unit: Decodable { var value: String }
        struct Loc: Decodable { var stringUnit: Unit? }
        struct Entry: Decodable { var localizations: [String: Loc]? }
        var strings: [String: Entry]
    }

    private static var catalogURL: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { u.deleteLastPathComponent() }   // → apps/ios/Packages
        return u.deletingLastPathComponent().appendingPathComponent("App/Localizable.xcstrings")
    }

    func testLocalizedExamplesParseToTheSameCommand() throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Self.catalogURL))
        func values(_ key: String) throws -> [String] {
            let locs = try XCTUnwrap(catalog.strings[key]?.localizations, key)
            XCTAssertEqual(locs.count, 13, "\(key) 需覆盖 13 种译文（另加中文源）")
            return [key] + locs.values.compactMap { $0.stringUnit?.value }
        }
        for v in try values("Gemini 走日本") {
            let p = CommandTokenizer.parse(v)
            XCTAssertEqual(p.serviceName, "Gemini", v); XCTAssertEqual(p.regionCode, "JP", v); XCTAssertFalse(p.wantsDirect, v)
        }
        for v in try values("GitHub 直连") {
            let p = CommandTokenizer.parse(v)
            XCTAssertEqual(p.host, "github.com", v); XCTAssertTrue(p.wantsDirect, v)
        }
        for v in try values("视频只用 4K 节点") {
            let p = CommandTokenizer.parse(v)
            XCTAssertTrue(p.wantsUHD, v); XCTAssertNil(p.serviceName, v); XCTAssertNil(p.regionCode, v)
        }
        for v in try values("香港") {
            let p = CommandTokenizer.parse(v)
            XCTAssertEqual(p.regionCode, "HK", v); XCTAssertNil(p.sceneId, v)
        }
    }

    func testRegisteredAliases() {
        XCTAssertEqual(CommandTokenizer.parse("Gemini عبر اليابان").regionCode, "JP")
        XCTAssertEqual(CommandTokenizer.parse("Claude آمریکا").regionCode, "US")
        XCTAssertEqual(CommandTokenizer.parse("ہانگ کانگ").regionCode, "HK")
        XCTAssertEqual(CommandTokenizer.parse("gpt 韩国").regionCode, "KR")
        XCTAssertEqual(CommandTokenizer.parse("claude de").regionCode, "DE")
        XCTAssertNil(CommandTokenizer.parse("video").regionCode, "de 只认独立单词")
        XCTAssertTrue(CommandTokenizer.parse("GitHub مستقیم").wantsDirect)
        XCTAssertTrue(CommandTokenizer.parse("الفيديو اليابان").isSceneWord)
        XCTAssertEqual(CommandTokenizer.parse("ویدیو ژاپن").sceneId, "video")
        XCTAssertEqual(CommandTokenizer.parse("الفيديو").tokens.first?.range, 0..<7, "取最靠前、最长的场景词")
    }
}
