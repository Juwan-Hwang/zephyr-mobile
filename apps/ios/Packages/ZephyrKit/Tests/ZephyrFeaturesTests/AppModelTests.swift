// AppModel 行为测试（MockEngine + 冻结时钟）：流落地、连接/断开、模式、导航与指令层状态（REVIEW-Q2 X-P1-8）。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
final class AppModelTests: XCTestCase {

    /// 轮询等待条件成立（流在后台 Task 里落地，不用固定 sleep）。
    private func until(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func testStartPopulatesScenesAndSubscriptions() async {
        let model = AppModel.preview(connected: true, frozen: true)
        model.start()
        let loaded = await until { !model.scenes.isEmpty && model.subscriptionsLoaded }
        XCTAssertTrue(loaded, "启动后场景与订阅流应落地")
        XCTAssertFalse(model.subscriptions.isEmpty)
    }

    func testConnectThenDisconnect() async {
        let model = AppModel.preview(connected: false, frozen: true)
        model.start()
        let initial = await until { model.connection.status == .disconnected }
        XCTAssertTrue(initial)
        XCTAssertFalse(model.isOn)

        await model.connect()
        let on = await until { model.connection.status == .connected }
        XCTAssertTrue(on)
        XCTAssertTrue(model.isOn)

        await model.disconnect()
        let off = await until { model.connection.status == .disconnected }
        XCTAssertTrue(off)
        XCTAssertNil(model.lastError)
    }

    func testSetModeUpdatesConnectionMode() async {
        let model = AppModel.preview(connected: true, frozen: true)
        model.start()
        _ = await until { model.connection.status == .connected }
        await model.setMode(.global)
        XCTAssertEqual(model.connection.mode, .global)
        await model.setMode(.direct)
        XCTAssertEqual(model.connection.mode, .direct)
    }

    func testSetModeToCurrentModeIsNoOp() async {
        let model = AppModel.preview(connected: true, frozen: true)
        model.start()
        _ = await until { model.connection.status == .connected }
        let current = model.connection.mode
        await model.setMode(current)
        XCTAssertEqual(model.connection.mode, current)
        XCTAssertNil(model.lastError)
    }

    func testOpenAndCloseCommandLayer() {
        let model = AppModel.preview(connected: true, frozen: true)
        model.sheet = .library
        model.openCommand(prefill: "gpt 日本")
        XCTAssertTrue(model.isCommandPresented)
        XCTAssertEqual(model.commandPrefill, "gpt 日本")
        XCTAssertNil(model.sheet, "打开指令层会收起浮层")
        model.closeCommand()
        XCTAssertFalse(model.isCommandPresented)
        XCTAssertEqual(model.commandPrefill, "")
    }

    func testPopToHomeResetsNavigationState() {
        let model = AppModel.preview(connected: true, frozen: true)
        model.sheet = .library
        model.returnsToLibrary = true
        model.isCommandPresented = true
        model.popToHome()
        XCTAssertNil(model.sheet)
        XCTAssertFalse(model.returnsToLibrary)
        XCTAssertFalse(model.isCommandPresented)
        XCTAssertTrue(model.path.isEmpty)
    }

    func testTrustedDeepLinkRunsWithoutConfirmation() async {
        let model = AppModel.preview(connected: true, frozen: true)
        model.start()
        _ = await until { model.connection.status == .connected }
        model.open(.mode("global"), source: .trusted)
        XCTAssertNil(model.pendingLink)
        let changed = await until { model.connection.mode == .global }
        XCTAssertTrue(changed)
    }

    func testConfirmingPendingLinkExecutesIt() async {
        let model = AppModel.preview(connected: true, frozen: true)
        model.start()
        _ = await until { model.connection.status == .connected }
        model.open(.mode("direct"), source: .external)
        XCTAssertEqual(model.pendingLink?.link, .mode("direct"))
        model.confirmPendingLink()
        XCTAssertNil(model.pendingLink)
        let changed = await until { model.connection.mode == .direct }
        XCTAssertTrue(changed)
    }
}
