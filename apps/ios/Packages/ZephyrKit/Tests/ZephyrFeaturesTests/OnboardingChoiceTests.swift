// 引导“简单 / 优选”写场景来源（#207 U3，对齐 Android applyOnboardingMode）与场景 sheet 漏斗新鲜度跟随 TTL（#207 U33）。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
final class OnboardingChoiceTests: XCTestCase {

    private func until(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// 引擎当前的场景（流的首帧即当前值）。
    private func engineScenes(_ model: AppModel) async -> [ZephyrKit.Scene] {
        for await list in model.engine.scenes() { return list }
        return []
    }

    func testChoiceMapsToSceneSource() {
        XCTAssertEqual(OnboardingChoice.simple.sceneSource, .subscriptionGroup)
        XCTAssertEqual(OnboardingChoice.best.sceneSource, .auto)
    }

    /// 简单：所有场景（mock 里 AI / 视频原为 auto）改为订阅分组。
    func testSimpleSetsEverySceneToSubscriptionGroup() async {
        let model = AppModel.preview(connected: false, frozen: true)
        model.start()
        _ = await until { !model.scenes.isEmpty }
        XCTAssertTrue(model.scenes.contains { $0.source == .auto }, "前提：mock 里有 auto 场景")
        await model.applyOnboardingChoice(.simple)
        let scenes = await engineScenes(model)
        XCTAssertFalse(scenes.isEmpty)
        XCTAssertTrue(scenes.allSatisfy { $0.source == .subscriptionGroup }, "\(scenes.map(\.source))")
    }

    /// 优选：场景流还没落地（model 未 start）时也从引擎取首帧，把订阅分组场景（mock 的“其他”）改为 auto。
    func testBestWorksBeforeScenesStreamLands() async {
        let model = AppModel.preview(connected: false, frozen: true)
        XCTAssertTrue(model.scenes.isEmpty)
        await model.applyOnboardingChoice(.best)
        let scenes = await engineScenes(model)
        XCTAssertFalse(scenes.isEmpty)
        XCTAssertTrue(scenes.allSatisfy { $0.source == .auto }, "\(scenes.map(\.source))")
    }

    // MARK: U33 漏斗新鲜度

    private func settings(ttl: Int32) -> ZephyrKit.Settings {
        ZephyrKit.Settings(onDemand: false, trustedWifi: [], disconnectOnTrusted: false, localProxyPort: 7890, localProxyAuth: false,
                 testOnWifiOnly: true, latencyTtlHours: ttl, autoUpdateHours: 12, updateOnWifiOnly: true,
                 showChangesBeforeUpdate: false, dns: DnsSettings(), tun: TunSettings(), accent: .blue,
                 appearance: .system, shareAnonymousPattern: false)
    }

    func testFunnelMaxAgeFollowsLatencyTtl() {
        XCTAssertEqual(SceneSheet.funnelMaxAgeMs(settings(ttl: 6)), 6 * 3_600_000)
        XCTAssertEqual(SceneSheet.funnelMaxAgeMs(settings(ttl: 72)), 72 * 3_600_000)
    }

    /// §15.e：0 = 默认 24；没有设置时同样 24。
    func testFunnelMaxAgeDefaultsTo24h() {
        XCTAssertEqual(SceneSheet.funnelMaxAgeMs(settings(ttl: 0)), 24 * 3_600_000)
        XCTAssertEqual(SceneSheet.funnelMaxAgeMs(nil), 24 * 3_600_000)
    }
}
