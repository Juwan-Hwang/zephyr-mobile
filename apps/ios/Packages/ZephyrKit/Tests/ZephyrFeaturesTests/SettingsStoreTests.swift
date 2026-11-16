// 设置写回（SettingsStore）：乐观更新、失败回滚并给出横幅错误、无变化不写回；
// 资料库设置摘要（LibraryModel）：受信任 Wi‑Fi 与本地端口两行文案。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var feed: Task<Void, Never>?

    override func tearDown() async throws {
        feed?.cancel(); feed = nil
        try await super.tearDown()
    }

    /// 启动订阅并等到第一帧设置。
    private func startedStore() async throws -> SettingsStore {
        let store = SettingsStore(engine: MockEngine(seed: 0, clock: .frozen941))
        feed = Task { await store.start() }
        for _ in 0..<200 where store.settings == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(store.settings, "应收到第一帧设置")
        return store
    }

    private static func base() -> Settings {
        Settings(onDemand: true, trustedWifi: ["家"], disconnectOnTrusted: true, localProxyPort: 7890, localProxyAuth: false,
                 testOnWifiOnly: true, latencyTtlHours: 24, autoUpdateHours: 12, updateOnWifiOnly: true, showChangesBeforeUpdate: true,
                 dns: DnsSettings(), tun: TunSettings(), accent: .blue, appearance: .system, shareAnonymousPattern: true)
    }

    func testUpdateBeforeFirstFrameIsRejected() async {
        let store = SettingsStore(engine: MockEngine(seed: 0, clock: .frozen941))
        let ok = await store.update { $0.onDemand.toggle() }
        XCTAssertFalse(ok)
        XCTAssertNil(store.settings)
        XCTAssertNil(store.lastError, "未收到设置时不应报错")
    }

    func testUnchangedUpdateSucceedsWithoutError() async throws {
        let store = try await startedStore()
        let before = store.settings
        let ok = await store.update { _ in }
        XCTAssertTrue(ok)
        XCTAssertEqual(store.settings, before)
        XCTAssertNil(store.lastError)
    }

    func testSuccessfulUpdateKeepsNewValue() async throws {
        let store = try await startedStore()
        let flipped = !(store.settings?.updateOnWifiOnly ?? false)
        let ok = await store.update { $0.updateOnWifiOnly = flipped }
        XCTAssertTrue(ok)
        XCTAssertEqual(store.settings?.updateOnWifiOnly, flipped)
        XCTAssertNil(store.lastError)
    }

    func testRejectedUpdateRollsBackAndReportsError() async throws {
        let store = try await startedStore()
        let before = store.settings
        let ok = await store.update { $0.localProxyPort = 0 }   // MockEngine 拒绝 0 端口
        XCTAssertFalse(ok)
        XCTAssertEqual(store.settings, before, "写回失败须回滚到旧值")
        XCTAssertNotNil(store.lastError, "失败须给出顶部横幅错误")
    }

    // MARK: LibraryModel 摘要文案（测试中 ZL.bundle 为 nil，即中文原文）

    func testTrustedWifiText() {
        var s = Self.base()
        XCTAssertEqual(LibraryModel.trustedWifiText(s), "家")
        s.trustedWifi = ["家", "公司", "咖啡馆"]
        XCTAssertEqual(LibraryModel.trustedWifiText(s), "家 等 3 个")
        s.trustedWifi = []
        XCTAssertEqual(LibraryModel.trustedWifiText(s), "无")
        s.trustedWifi = ["家"]
        s.disconnectOnTrusted = false
        XCTAssertEqual(LibraryModel.trustedWifiText(s), "关", "功能关闭时不显示列表")
    }

    func testLocalProxyText() {
        var s = Self.base()
        s.localProxyEnabled = false
        XCTAssertEqual(LibraryModel.localProxyText(s), "关")
        s.localProxyEnabled = true
        XCTAssertEqual(LibraryModel.localProxyText(s), "7890")
    }
}
