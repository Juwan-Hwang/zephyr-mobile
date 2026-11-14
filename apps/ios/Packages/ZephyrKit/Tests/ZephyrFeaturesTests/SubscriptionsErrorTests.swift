// 订阅页错误走顶部横幅（PageError），成功结果才走吐司（REVIEW L-P2-11）。

import XCTest
import ZephyrKit
import ZephyrMock
@testable import ZephyrFeatures

@MainActor
final class SubscriptionsErrorTests: XCTestCase {
    private func makeModel() -> SubscriptionsModel {
        SubscriptionsModel(engine: MockEngine(seed: 0, clock: .frozen941), now: { 0 })
    }

    func testEngineErrorGoesToBannerNotToast() {
        let model = makeModel()
        model.report(ZephyrError(code: .subscriptionFetchFailed, message: "x"))
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.toast)
    }

    func testCancellationIsSilent() {
        let model = makeModel()
        model.report(CancellationError())
        model.report(ZephyrError(code: .cancelled))
        XCTAssertNil(model.error)
        XCTAssertNil(model.toast)
    }

    func testUnknownErrorUsesFallback() {
        struct Boom: Error {}
        let model = makeModel()
        model.report(Boom())
        XCTAssertEqual(model.error?.message, ZL.tr("操作失败"))
    }
}
