// 返回 String 的文案走 ZL（测试进程 ZL.bundle == nil → 原样中文）：守住文案与格式不被改坏。

import XCTest
@testable import ZephyrFeatures
import ZephyrKit

@MainActor
final class TextTests: XCTestCase {
    private let sh = TimeZone(identifier: "Asia/Shanghai")!
    /// 2026-11-06 09:41 +08:00（周五）
    private let now: Int64 = 1_793_929_260_000
    private let day: Int64 = 86_400_000

    func testHomeExpiryUsesWeekdayWithinAWeek() {
        XCTAssertEqual(HFormat.homeExpiry(now + 3 * day, now: now, timeZone: sh), "周一到期")
        XCTAssertEqual(HFormat.homeExpiry(now + 1 * day, now: now, timeZone: sh), "周六到期")
    }

    func testHomeExpiryFallsBackToFormatOutsideAWeek() {
        XCTAssertEqual(HFormat.homeExpiry(now + 26 * day, now: now, timeZone: sh), "26 天后到期")
        XCTAssertEqual(HFormat.homeExpiry(now - 1, now: now, timeZone: sh), "已到期")
    }

    func testServiceSummarySpokenText() {
        func svc(_ n: String, _ ok: Bool) -> ServiceHealth { ServiceHealth(appId: n, name: n, ok: ok, checkedAt: now) }
        XCTAssertEqual(SceneServiceSummary([svc("Claude", false), svc("GPT", true), svc("Gemini", true)]).spoken,
                       "Claude 不可用，GPT、Gemini 正常")
        XCTAssertEqual(SceneServiceSummary([svc("GPT", true), svc("Gemini", true)]).spoken, "GPT、Gemini 均正常")
        XCTAssertEqual(SceneServiceSummary([svc("Netflix", true)]).spoken, "Netflix 正常")
        XCTAssertEqual(SceneServiceSummary([svc("Claude", false)]).unavailableText, "Claude 不可用")
        XCTAssertNil(SceneServiceSummary([]).spoken)
    }

    func testDeepLinkPromptsFollowZL() {
        let p = DeepLinkPolicy.prompt(for: .mode("global"), isOn: true)
        XCTAssertEqual(p?.title, "切换到全局模式？")
        XCTAssertEqual(p?.confirm, "切换")
        XCTAssertEqual(DeepLinkPolicy.prompt(for: .disconnect, isOn: true)?.destructive, true)
    }

    func testImportErrorMessages() {
        XCTAssertEqual(SubscriptionImporter.message(for: .networkUnavailable), "网络不可用")
        XCTAssertEqual(SubscriptionImporter.message(for: .internal), "导入失败")
    }
}
