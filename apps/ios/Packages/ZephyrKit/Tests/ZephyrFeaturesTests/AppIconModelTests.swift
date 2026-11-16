// 设置 › 应用图标（REVIEW L-P2-14）：可选项随资源 / 系统支持变化，切换失败回滚并给出横幅错误，取消不打扰。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

@MainActor
private final class FakeSwitcher: AppIconSwitching {
    var supportsAlternateIcons = true
    var alternateIconName: String?
    var bundled: Set<String> = ["AppIcon-Light"]
    var failure: Error?
    private(set) var calls: [String?] = []

    func hasIcon(named name: String) -> Bool { bundled.contains(name) }

    func setAlternateIconName(_ name: String?) async throws {
        calls.append(name)
        if let failure { throw failure }
        alternateIconName = name
    }
}

private struct SomeError: Error {}

@MainActor
final class AppIconModelTests: XCTestCase {
    func testOptionMapsAlternateName() {
        XCTAssertEqual(AppIconOption(alternateName: nil), .dark)
        XCTAssertEqual(AppIconOption(alternateName: "AppIcon-Light"), .light)
        XCTAssertEqual(AppIconOption(alternateName: "Unknown"), .dark, "未知备用图标回落到主图标")
    }

    func testInitReadsCurrentIcon() {
        let s = FakeSwitcher()
        s.alternateIconName = "AppIcon-Light"
        XCTAssertEqual(AppIconModel(switcher: s).current, .light)
    }

    func testOptionsHideMissingResourceAndUnsupportedSystem() {
        let s = FakeSwitcher()
        XCTAssertEqual(AppIconModel(switcher: s).options, [.dark, .light])
        XCTAssertTrue(AppIconModel(switcher: s).isSelectable)

        s.bundled = []
        XCTAssertEqual(AppIconModel(switcher: s).options, [.dark])
        XCTAssertFalse(AppIconModel(switcher: s).isSelectable, "资源缺失时行不可点")

        s.bundled = ["AppIcon-Light"]
        s.supportsAlternateIcons = false
        XCTAssertEqual(AppIconModel(switcher: s).options, [.dark])
        XCTAssertFalse(AppIconModel(switcher: s).isSelectable)
    }

    func testSelectSwitchesIcon() async {
        let s = FakeSwitcher()
        let m = AppIconModel(switcher: s)
        let err = await m.select(.light)
        XCTAssertNil(err)
        XCTAssertEqual(m.current, .light)
        XCTAssertFalse(m.isChanging)
        XCTAssertEqual(s.calls, ["AppIcon-Light"])

        _ = await m.select(.dark)
        XCTAssertEqual(s.calls, ["AppIcon-Light", nil], "切回主图标传 nil")
    }

    func testSelectSameOrUnavailableIsNoOp() async {
        let s = FakeSwitcher()
        s.bundled = []
        let m = AppIconModel(switcher: s)
        _ = await m.select(.dark)
        _ = await m.select(.light)
        XCTAssertTrue(s.calls.isEmpty)
        XCTAssertEqual(m.current, .dark)
    }

    func testFailureRollsBackAndReturnsFallbackMessage() async {
        let s = FakeSwitcher()
        s.failure = SomeError()
        let m = AppIconModel(switcher: s)
        let err = await m.select(.light)
        XCTAssertEqual(m.current, .dark, "失败回滚")
        XCTAssertFalse(m.isChanging)
        XCTAssertEqual(err?.message, ZL.tr("无法更换应用图标"))
        XCTAssertNil(err?.retryTitle)
    }

    func testCancellationRollsBackSilently() async {
        let s = FakeSwitcher()
        s.failure = CancellationError()
        let m = AppIconModel(switcher: s)
        let err = await m.select(.light)
        XCTAssertNil(err, "取消不出横幅")
        XCTAssertEqual(m.current, .dark)
    }
}
