// #1 真机反馈（2026-11-25）：订阅页标出当前订阅「使用中」（契约 §14：生效订阅 = 列表第一个），
// 删除当前订阅后标记移到下一个；首页设置按钮用标准齿轮。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class SubscriptionsActiveTests: XCTestCase {
    private func makeModel() -> SubscriptionsModel {
        SubscriptionsModel(engine: MockEngine(seed: 0, clock: .frozen941), now: { 0 })
    }

    func testFirstSubscriptionIsActiveAndMarked() async throws {
        let model = makeModel()
        let task = Task { await model.start() }
        defer { task.cancel() }
        try await waitUntil { model.loaded }
        let first = try XCTUnwrap(model.subscriptions.first)
        XCTAssertEqual(model.activeID, first.id)
        XCTAssertTrue(model.isActive(first))
        XCTAssertTrue(model.detail(first).hasPrefix(ZL.tr("使用中") + " · "), model.detail(first))
        for other in model.subscriptions.dropFirst().prefix(5) {
            XCTAssertFalse(model.isActive(other))
            XCTAssertFalse(model.detail(other).contains(ZL.tr("使用中")), model.detail(other))
        }
    }

    func testDeletingActiveMovesMarkToNext() async throws {
        let model = makeModel()
        let task = Task { await model.start() }
        defer { task.cancel() }
        try await waitUntil { model.subscriptions.count >= 2 }
        let first = model.subscriptions[0], second = model.subscriptions[1]
        await model.delete(first)
        try await waitUntil { model.subscriptions.first?.id == second.id }
        XCTAssertEqual(model.activeID, second.id)
        XCTAssertTrue(model.detail(second).hasPrefix(ZL.tr("使用中")))
    }

    func testNoSubscriptionsMeansNoActive() {
        let model = makeModel()
        XCTAssertNil(model.activeID)
        let s = Subscription(id: "x", name: "X", nodeCount: 1, autoUpdateHours: 12)
        XCTAssertFalse(model.isActive(s))
        XCTAssertFalse(model.detail(s).contains(ZL.tr("使用中")))
    }

    /// 契约 §22.a：点选第三个订阅 → 它移到第一位并标「使用中」，其余相对顺序不变，吐司提示。
    func testTapSetsActiveSubscription() async throws {
        let model = makeModel()
        let task = Task { await model.start() }
        defer { task.cancel() }
        try await waitUntil { model.subscriptions.count >= 3 }
        let before = model.subscriptions.map(\.id)
        let target = model.subscriptions[2]
        await model.activate(target)
        XCTAssertEqual(model.activeID, target.id)
        XCTAssertEqual(model.subscriptions.map(\.id), [target.id] + before.filter { $0 != target.id })
        XCTAssertTrue(model.detail(target).hasPrefix(ZL.tr("使用中") + " · "))
        XCTAssertFalse(model.detail(model.subscriptions[1]).contains(ZL.tr("使用中")))
        XCTAssertEqual(model.toast?.message, ZL.s("已切换至%@", target.name))
        XCTAssertNil(model.error)
        // 订阅流随后推来的列表与返回值一致，标记不会跳回去。
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.activeID, target.id)
    }

    func testTapOnActiveSubscriptionDoesNothing() async throws {
        let model = makeModel()
        let task = Task { await model.start() }
        defer { task.cancel() }
        try await waitUntil { model.loaded }
        let before = model.subscriptions.map(\.id)
        await model.activate(model.subscriptions[0])
        XCTAssertEqual(model.subscriptions.map(\.id), before)
        XCTAssertNil(model.toast)
        XCTAssertNil(model.error)
    }

    /// 不存在（例如另一处刚删掉）→ subscription_not_found，走顶部横幅，列表不变。
    func testActivateMissingSubscriptionShowsBanner() async throws {
        let model = makeModel()
        let task = Task { await model.start() }
        defer { task.cancel() }
        try await waitUntil { model.loaded }
        let before = model.subscriptions.map(\.id)
        await model.activate(Subscription(id: "gone", name: "Gone", nodeCount: 1, autoUpdateHours: 12))
        XCTAssertEqual(model.error?.message, ZephyrError(code: .subscriptionNotFound, message: "").userMessage)
        XCTAssertEqual(model.subscriptions.map(\.id), before)
        XCTAssertNil(model.toast)
    }

    func testSettingsButtonUsesGear() {
        XCTAssertEqual(HomeHeader.settingsSymbol, "gearshape")
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timeout"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
