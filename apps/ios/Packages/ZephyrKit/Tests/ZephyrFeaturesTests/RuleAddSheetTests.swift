// 添加覆写：输入规范化（去协议 / 路径 / 端口 / 大小写 / 尾点），不合法返回 nil。

import XCTest
@testable import ZephyrFeatures

final class RuleAddSheetTests: XCTestCase {
    func testNormalizesCommonPastes() {
        XCTAssertEqual(RuleAddSheet.normalizedHost("  Example.COM "), "example.com")
        XCTAssertEqual(RuleAddSheet.normalizedHost("https://www.Example.com/path?q=1#x"), "www.example.com")
        XCTAssertEqual(RuleAddSheet.normalizedHost("example.com:8443"), "example.com")
        XCTAssertEqual(RuleAddSheet.normalizedHost("user:pw@host.example.org/"), "host.example.org")
        XCTAssertEqual(RuleAddSheet.normalizedHost("example.com."), "example.com")
        XCTAssertEqual(RuleAddSheet.normalizedHost("1.2.3.4"), "1.2.3.4")
    }

    func testRejectsInvalid() {
        XCTAssertNil(RuleAddSheet.normalizedHost(""))
        XCTAssertNil(RuleAddSheet.normalizedHost("   "))
        XCTAssertNil(RuleAddSheet.normalizedHost("exa mple.com"))
        XCTAssertNil(RuleAddSheet.normalizedHost("exa$mple.com"))
        XCTAssertNil(RuleAddSheet.normalizedHost(String(repeating: "a", count: 260)))
    }
}
