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

    /// 契约 §22.b：错误详情只经传入的脱敏函数（真机 = 核心 redactDiagnostic），平台不再自己折叠 / 截断。
    func testFailureDetailGoesThroughRedactor() {
        var seen: [String] = []
        let d = ZephyrError(code: .coreCrashed, message: "fetch https://x/sub?token=S").failureDetail { seen.append($0); return "R" }
        XCTAssertEqual(seen, ["fetch https://x/sub?token=S"], "原文原样交给脱敏函数")
        XCTAssertEqual(d, "R", "直接用脱敏结果")
        let long = String(repeating: "x", count: 500)
        XCTAssertEqual(ZephyrError(code: .coreCrashed, message: long).failureDetail { $0 }?.count, 500, "截断由核心负责")
        XCTAssertNil(ZephyrError(code: .coreCrashed, message: " \n ").failureDetail { $0 })
        XCTAssertNil(ZephyrError(code: .coreCrashed, message: "x").failureDetail { _ in " " }, "脱敏后为空不显示")
    }
}
