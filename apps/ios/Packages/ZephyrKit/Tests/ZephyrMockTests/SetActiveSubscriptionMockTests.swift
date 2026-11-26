// 契约 §22.a：MockEngine 的 setActiveSubscription 与核心同语义（移到第一位、其余相对顺序不变、不存在 → subscription_not_found）。

import XCTest
import ZephyrKit
@testable import ZephyrMock

final class SetActiveSubscriptionMockTests: XCTestCase {
    func first<T>(_ s: AsyncStream<T>) async -> T? { for await v in s { return v }; return nil }

    func testMovesToFrontKeepingOrder() async throws {
        let e = MockEngine(seed: 0, clock: .frozen941)
        let initial = await first(e.subscriptions())
        let before = try XCTUnwrap(initial).map(\.id)
        XCTAssertGreaterThanOrEqual(before.count, 3)
        let target = before[2]
        let list = try await e.setActiveSubscription(id: target)
        XCTAssertEqual(list.map(\.id), [target] + before.filter { $0 != target })
        let streamed = await first(e.subscriptions())
        XCTAssertEqual(streamed?.map(\.id), list.map(\.id), "订阅流推新顺序")
        // 已是第一位：顺序不变。
        let again = try await e.setActiveSubscription(id: target)
        XCTAssertEqual(again.map(\.id), list.map(\.id))
    }

    func testMissingIsSubscriptionNotFound() async {
        let e = MockEngine(seed: 0, clock: .frozen941)
        do { _ = try await e.setActiveSubscription(id: "nope"); XCTFail("应抛") } catch let err as ZephyrError {
            XCTAssertEqual(err.code, .subscriptionNotFound)
        } catch { XCTFail("\(error)") }
    }

    func testRedactDiagnosticFoldsAndTruncates() {
        let e = MockEngine(seed: 0, clock: .frozen941)
        XCTAssertEqual(e.redactDiagnostic(text: "a\n  b\tc"), "a b c")
        let long = e.redactDiagnostic(text: String(repeating: "x", count: 500))
        XCTAssertEqual(long.count, 241)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}
