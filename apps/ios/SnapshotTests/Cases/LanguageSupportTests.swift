// 快照语言支持本身的单测：伪语言保留占位符、英文查表可用。

import XCTest
import ZephyrKit

@MainActor
final class LanguageSupportTests: XCTestCase {
    func testPseudoKeepsPlaceholders() {
        let out = ZPseudo.transform("%1$@ of %2$@ · %lld nodes, 50%%")
        XCTAssertTrue(out.hasPrefix("⟦") && out.hasSuffix("⟧"))
        for p in ["%1$@", "%2$@", "%lld", "%%"] { XCTAssertTrue(out.contains(p), "缺少占位符 \(p)：\(out)") }
        XCTAssertTrue(out.contains("ñödés"))
    }

    func testEnglishBundleResolves() {
        XCTAssertTrue(ZSnapshotLocalizedBundle.hasEnglish, "测试 bundle 缺 en.lproj")
        let previous = ZSnapshotLocalizedBundle.use(.en)
        defer { ZSnapshotLocalizedBundle.use(previous) }
        XCTAssertEqual(ZL.tr("已连接"), Bundle.main.localizedString(forKey: "已连接", value: nil, table: nil))
        XCTAssertNotEqual(ZL.tr("已连接"), "已连接", "英文变体仍输出中文")
    }

    func testPseudoBundleTransformsTable() {
        let previous = ZSnapshotLocalizedBundle.use(.pseudo)
        defer { ZSnapshotLocalizedBundle.use(previous) }
        let value = ZL.tr("已连接")
        XCTAssertTrue(value.hasPrefix("⟦"), value)
        XCTAssertEqual(Bundle.main.localizedString(forKey: "已连接", value: nil, table: nil), value)
    }

    func testPseudoPluralKeepsVariables() {
        let entry: [String: Any] = [
            "NSStringLocalizedFormatKey": "%#@count@",
            "count": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld",
                      "one": "Every Hour", "other": "Every %lld Hours"],
        ]
        let out = ZPseudo.transformPluralEntry(entry) as? [String: Any]
        XCTAssertEqual(out?["NSStringLocalizedFormatKey"] as? String, "%#@count@")
        let v = out?["count"] as? [String: String]
        XCTAssertEqual(v?["NSStringFormatValueTypeKey"], "lld")
        XCTAssertTrue(v?["other"]?.contains("%lld") ?? false)
        XCTAssertTrue(v?["one"]?.hasPrefix("⟦") ?? false)
        XCTAssertTrue(ZPseudo.transform("%#@count@").contains("%#@count@"))

        let previous = ZSnapshotLocalizedBundle.use(.pseudo)
        defer { ZSnapshotLocalizedBundle.use(previous) }
        let hours = ZL.f("每 %lld 小时", Int64(12))
        XCTAssertTrue(hours.hasPrefix("⟦") && hours.contains("12"), hours)
    }

    func testChineseIsUntouched() {
        ZSnapshotLocalizedBundle.use(.zh)
        XCTAssertNil(ZL.bundle)
        XCTAssertFalse(Bundle.main.bundleURL.lastPathComponent.hasPrefix("zephyr-snapshot-"))
        XCTAssertEqual(ZL.tr("已连接"), "已连接")
    }
}
