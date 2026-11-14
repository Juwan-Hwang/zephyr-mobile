// 紧凑计数按界面语言选单位：中文“万 / 亿”，英文 K / M / B（英文界面不再出现“312 万”）。

import XCTest
import ZephyrKit
@testable import ZephyrFeatures

final class CompactCountTests: XCTestCase {
    func testChineseUnitsUnchanged() {
        XCTAssertEqual(CompactCount.zh(214), "214")
        XCTAssertEqual(CompactCount.zh(99_999), "99,999")
        XCTAssertEqual(CompactCount.zh(13_109_802), "1,311 万")
        XCTAssertEqual(CompactCount.zh(103_606_731), "1.04 亿")
        XCTAssertEqual(CompactCount.chipZh(3_118_402), "312 万")
        XCTAssertEqual(CompactCount.chipZh(9_999), "9,999")
    }

    func testEnglishUnits() {
        XCTAssertEqual(CompactCount.en(214), "214")
        XCTAssertEqual(CompactCount.en(99_999), "99,999")
        XCTAssertEqual(CompactCount.en(312_000), "312K")
        XCTAssertEqual(CompactCount.en(13_109_802), "13.1M")
        XCTAssertEqual(CompactCount.en(103_606_731), "104M")
        XCTAssertEqual(CompactCount.en(1_040_000_000), "1.04B")
        XCTAssertEqual(CompactCount.chipEn(9_999), "9,999")
        XCTAssertEqual(CompactCount.chipEn(702_315), "702K")
        XCTAssertEqual(CompactCount.chipEn(3_118_402), "3.1M")
    }

    func testEnglishNeverUsesChineseUnits() {
        for n: Int64 in [0, 9_999, 10_000, 99_999, 100_000, 999_999, 1_000_000, 99_999_999, 100_000_000, 13_109_802_000] {
            for s in [CompactCount.en(n), CompactCount.chipEn(n)] {
                XCTAssertFalse(s.contains("万") || s.contains("亿"), "\(n) → \(s)")
            }
        }
    }

    /// 测试里 ZL.bundle 为 nil：保持中文单位，现有断言与快照不受影响。
    func testDefaultsToChineseWithoutBundle() {
        XCTAssertNil(ZL.bundle)
        XCTAssertTrue(ZL.usesChineseUnits)
        XCTAssertEqual(CompactCount.chip(3_118_402), "312 万")
        XCTAssertEqual(LibraryModel.compact(13_109_802), "1,311 万")
    }
}
