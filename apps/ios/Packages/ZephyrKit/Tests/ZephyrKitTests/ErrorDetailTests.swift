import XCTest
@testable import ZephyrKit

/// #1 A 真机结论 ③：失败原文进“错误详情”，`geodata missing:` 单独识别。
final class ErrorDetailTests: XCTestCase {
    func testGeodataMissingOnlyForCoreCrashed() {
        XCTAssertTrue(ZephyrError(code: .coreCrashed, message: "geodata missing: GeoSite.dat（GEOSITE 规则要用）").isGeodataMissing)
        XCTAssertTrue(ZephyrError(code: .coreCrashed, message: "  Geodata Missing: x").isGeodataMissing)
        XCTAssertFalse(ZephyrError(code: .coreCrashed, message: "can't download MMDB").isGeodataMissing)
        XCTAssertFalse(ZephyrError(code: .coreCrashed, message: "rules[3]: geodata missing: x").isGeodataMissing, "只认前缀")
        XCTAssertFalse(ZephyrError(code: .internal, message: "geodata missing: x").isGeodataMissing)
    }

    func testFailureDetailFoldsAndTruncates() {
        XCTAssertNil(ZephyrError(code: .coreCrashed, message: " \n ").failureDetail)
        XCTAssertEqual(ZephyrError(code: .coreCrashed, message: "a\n  b\tc").failureDetail, "a b c")
        let long = String(repeating: "x", count: 500)
        let d = ZephyrError(code: .coreCrashed, message: long).failureDetail
        XCTAssertEqual(d?.count, ZephyrError.failureDetailMaxChars)
        XCTAssertTrue(d?.hasSuffix("…") == true)
        let exact = String(repeating: "y", count: ZephyrError.failureDetailMaxChars)
        XCTAssertEqual(ZephyrError(code: .coreCrashed, message: exact).failureDetail, exact)
    }
}
