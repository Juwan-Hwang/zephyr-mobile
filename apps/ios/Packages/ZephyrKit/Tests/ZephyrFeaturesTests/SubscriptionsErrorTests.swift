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

    /// 契约 §18.b state.failed：手动更新失败后行内写「失败」（替代到期），原因仍走横幅。
    func testFailedUpdateShowsInlineFailedTerm() async {
        let model = makeModel()
        let ghost = Subscription(id: "no-such-sub", name: "Ghost", nodeCount: 12, expiresAt: 86_400_000, autoUpdateHours: 12)
        await model.update(ghost)
        XCTAssertTrue(model.failedUpdates.contains(ghost.id))
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.detail(ghost).contains(ZL.tr("失败")), model.detail(ghost))
        XCTAssertFalse(model.detail(ghost).contains(ZFormat.expiry(86_400_000, now: 0)))
    }
}
