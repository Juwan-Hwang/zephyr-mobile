// 契约 §15.h 4K 名字判定：与共享样本 contract/fixtures/uhd-names-v1.json 逐条比对（同 core-mobile subscription.rs uhd_fixtures）。
// 规则：名字含 4K / UHD / 8K，仅 ASCII 不区分大小写；全角 ４Ｋ、分隔开的 "4 K" 不算。
// 样本用 #filePath 定位仓库根读取（同 Fixtures.swift），SwiftPM 与 CI 不依赖测试资源拷贝。

import XCTest
import Foundation
@testable import ZephyrMock

final class UHDFixtureTests: XCTestCase {

    static let url = Fixtures.repoRoot.appendingPathComponent("contract/fixtures/uhd-names-v1.json")

    func loadCases() throws -> [(name: String, uhd: Bool)] {
        let data = try Data(contentsOf: Self.url)
        let doc = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(doc["version"] as? Int, 1)
        let raw = try XCTUnwrap(doc["cases"] as? [[String: Any]])
        return try raw.map { c in
            (try XCTUnwrap(c["name"] as? String), try XCTUnwrap(c["uhd"] as? Bool))
        }
    }

    func testMockMatchesSharedFixture() throws {
        let cases = try loadCases()
        XCTAssertGreaterThanOrEqual(cases.count, 10, "样本过少：\(Self.url.path)")
        for c in cases {
            XCTAssertEqual(MockEngine.isUHD(c.name), c.uhd, "isUHD(\(String(reflecting: c.name)))")
        }
    }

    /// 仅 ASCII：非 ASCII 字符经大小写映射或规范等价也不应凑成 4K（开尔文符号 U+212A、全角小写 ｋ）。
    func testNonASCIIDoesNotFold() {
        XCTAssertFalse(MockEngine.isUHD("U\u{0048}\u{0301}D"), "H 带组合重音")
        XCTAssertTrue(MockEngine.isUHD("x8k"))
        XCTAssertFalse(MockEngine.isUHD("4\u{212A}"), "开尔文符号 U+212A 与 K 规范等价，但非 ASCII")
        XCTAssertFalse(MockEngine.isUHD("４ｋ"), "全角")
        XCTAssertTrue(MockEngine.isUHD("uHd"))
    }
}
